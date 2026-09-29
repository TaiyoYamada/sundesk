"""SudachiPy で形態素解析し、用語の候補（名詞の連続と英字の語）を取り出す。

候補は、名詞の連続（最長のもの）と、その中の連続した部分列。C-value は、長い候補の中に
含まれる短い候補の数え方を補正するので、部分列も候補として数える。
"""

import re
import threading
import unicodedata
from collections.abc import Iterator
from dataclasses import dataclass
from functools import cache
from typing import Any

MAX_TERM_TOKENS = 6
"""候補にする部分列の最大のトークン数"""

_LATIN_WORD = re.compile(r"[A-Za-z][A-Za-z0-9+#.\-]*")
_SENTENCE = re.compile(r"[^。．！？!?\n]+[。．！？!?]?")
_ASCII_UPPER = re.compile(r"[A-Z]+")
_SPACES = re.compile(r"\s+")
_ONLY_HIRAGANA = re.compile(r"[぀-ゟ]+")
_LATIN_TERM = re.compile(r"[a-z0-9+#.\- ]+")
_URL = re.compile(r"(?:https?://|www\.)[^\s<>()\[\]「」（）]+|[\w.+-]+@[\w-]+\.[\w.-]+")
_HAS_CONTENT = re.compile(r"[A-Za-z㐀-鿿゠-ヿ豈-﫿]")
# Sudachi の 1 回の入力の上限（バイト数）より十分に短く区切る
_MAX_SEGMENT_CHARS = 4000

STOPWORDS = frozenset(
    {
        "こと",
        "もの",
        "ため",
        "よう",
        "とき",
        "ところ",
        "場合",
        "など",
        "それぞれ",
        "一つ",
        "ひとつ",
        "一種",
        "以下",
        "以上",
        "今回",
        "前者",
        "後者",
        "自分",
        "方法",
        "感じ",
        # 研究ノートの見出しや決まった言い回し（どのノートにも出て、概念にならない）
        "仮説",
        "考察",
        "メモ",
        "要点",
        "結果",
        "実験",
        "記録",
        "課題",
        "予定",
        "確認",
        "今日",
        "次回",
    }
)

ENGLISH_STOPWORDS = frozenset(
    {
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "by",
        "ed",
        "eds",
        "et",
        "al",
        "for",
        "from",
        "in",
        "is",
        "it",
        "of",
        "on",
        "or",
        "pp",
        "that",
        "the",
        "this",
        "to",
        "via",
        "we",
        "with",
    }
)


def normalize(text: str) -> str:
    """機械的に同じと言えるものだけをまとめる。NFKC、英字の小文字化、空白の統一。"""
    folded = unicodedata.normalize("NFKC", text)
    folded = _ASCII_UPPER.sub(lambda match: match.group().lower(), folded)
    return _SPACES.sub(" ", folded).strip()


@dataclass(frozen=True)
class Token:
    surface: str
    pos: tuple[str, ...]
    start: int
    end: int

    @property
    def is_latin(self) -> bool:
        return _LATIN_WORD.fullmatch(self.surface) is not None

    @property
    def is_noun(self) -> bool:
        if self.is_latin:
            return True
        return self.pos[0] == "名詞" and self.pos[1] != "数詞"

    @property
    def is_prefix(self) -> bool:
        return self.pos[0] == "接頭辞"

    @property
    def is_suffix(self) -> bool:
        return self.pos[0] == "接尾辞" and self.pos[1] == "名詞的"

    @property
    def joins_latin(self) -> bool:
        """英字の語の間にあれば、前後をつなぐもの（空白 1 つとハイフン）。"""
        return self.pos[0] == "空白" or self.surface == "-"


@dataclass(frozen=True)
class Occurrence:
    """候補が 1 回出てきたところ。"""

    key: str
    """正規化した形"""
    surface: str
    start: int
    end: int
    length: int
    """トークンの数"""
    children: tuple[str, ...]
    """この候補に含まれる、より短い候補の正規化した形"""


@cache
def _dictionary() -> Any:
    from sudachipy import Dictionary  # pyright: ignore[reportMissingTypeStubs]

    return Dictionary(dict="core")


_dictionary_lock = threading.Lock()


def _new_tokenizer() -> Any:
    from sudachipy import SplitMode  # pyright: ignore[reportMissingTypeStubs]

    with _dictionary_lock:
        return _dictionary().tokenizer(mode=SplitMode.B)


def sentences(text: str) -> Iterator[tuple[int, str]]:
    """文に区切り、(先頭の位置, 文) を返す。"""
    for match in _SENTENCE.finditer(text):
        sentence = match.group()
        if sentence.strip():
            yield match.start(), sentence


def _is_valid_term(surface: str, key: str) -> bool:
    if len(key) < 2 or key in STOPWORDS:
        return False
    if _ONLY_HIRAGANA.fullmatch(key):
        return False
    if _LATIN_TERM.fullmatch(key):
        words = key.split(" ")
        if words[0] in ENGLISH_STOPWORDS or words[-1] in ENGLISH_STOPWORDS:
            return False
        # 2 文字以下の英字の語は、略語（大文字）だけを採る（「et」「al」などを避ける）
        if len(words) == 1 and len(key) <= 2 and not surface.isupper():
            return False
    return _HAS_CONTENT.search(surface) is not None


def mask_urls(text: str) -> str:
    """URL とメールアドレスを、同じ長さの空白に置き換える（位置を変えないため）。"""
    return _URL.sub(lambda match: " " * len(match.group()), text)


class TermExtractor:
    """1 つのスレッドの中で使う。Sudachi のトークナイザは複数のスレッドから同時に使えない。"""

    def __init__(self) -> None:
        self._tokenizer = _new_tokenizer()

    def tokens(self, text: str) -> list[Token]:
        tokens: list[Token] = []
        for offset, sentence in sentences(mask_urls(text)):
            for start in range(0, len(sentence), _MAX_SEGMENT_CHARS):
                segment = sentence[start : start + _MAX_SEGMENT_CHARS]
                base = offset + start
                for morpheme in self._tokenizer.tokenize(segment):
                    tokens.append(
                        Token(
                            surface=str(morpheme.surface()),
                            pos=tuple(str(part) for part in morpheme.part_of_speech()),
                            start=base + int(morpheme.begin()),
                            end=base + int(morpheme.end()),
                        )
                    )
        return tokens

    def runs(self, text: str) -> list[list[Token]]:
        """名詞の連続を取り出す。英字の語の間の空白やハイフンはつなぐ。"""
        runs: list[list[Token]] = []
        current: list[Token] = []
        tokens = self.tokens(text)
        for index, token in enumerate(tokens):
            if token.is_noun or token.is_prefix or (token.is_suffix and current):
                if current and current[-1].end != token.start and not self._joined(tokens, index):
                    runs.append(current)
                    current = []
                current.append(token)
            elif (
                token.joins_latin
                and current
                and current[-1].is_latin
                and index + 1 < len(tokens)
                and tokens[index + 1].is_latin
            ):
                continue
            elif current:
                runs.append(current)
                current = []
        if current:
            runs.append(current)
        return [trimmed for run in runs if (trimmed := self._trim(run))]

    @staticmethod
    def _joined(tokens: list[Token], index: int) -> bool:
        previous = tokens[index - 1] if index > 0 else None
        return previous is not None and previous.joins_latin and tokens[index].is_latin

    @staticmethod
    def _trim(run: list[Token]) -> list[Token]:
        start, end = 0, len(run)
        while start < end and run[start].is_suffix:
            start += 1
        while end > start and run[end - 1].is_prefix:
            end -= 1
        return run[start:end]

    def occurrences(self, text: str) -> list[Occurrence]:
        """名詞の連続と、その部分列のすべての出現を返す。"""
        result: list[Occurrence] = []
        for run in self.runs(text):
            spans: list[tuple[int, int]] = []
            for i in range(len(run)):
                if run[i].is_suffix:
                    continue
                for j in range(i + 1, min(len(run), i + MAX_TERM_TOKENS) + 1):
                    if run[j - 1].is_prefix:
                        continue
                    spans.append((i, j))
            keyed: dict[tuple[int, int], tuple[str, str]] = {}
            for i, j in spans:
                surface = text[run[i].start : run[j - 1].end]
                key = normalize(surface)
                if _is_valid_term(surface, key):
                    keyed[(i, j)] = (surface, key)
            for (i, j), (surface, key) in keyed.items():
                children = tuple(
                    sorted(
                        {
                            child_key
                            for (a, b), (_s, child_key) in keyed.items()
                            if i <= a and b <= j and (a, b) != (i, j) and child_key != key
                        }
                    )
                )
                result.append(
                    Occurrence(
                        key=key,
                        surface=surface,
                        start=run[i].start,
                        end=run[j - 1].end,
                        length=j - i,
                        children=children,
                    )
                )
        result.sort(key=lambda occurrence: (occurrence.start, -occurrence.end))
        return result
