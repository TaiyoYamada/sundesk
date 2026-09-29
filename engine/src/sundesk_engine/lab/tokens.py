"""プロンプトのトークン化と、トークンの表示用の文字列。"""

import weakref
from dataclasses import dataclass
from typing import Any

from sundesk_engine.errors import BadRequestError, UnsupportedError

MAX_PROMPT_TOKENS = 512
REPLACEMENT_CHARACTER = "\ufffd"


@dataclass(frozen=True)
class TokenSpan:
    id: int
    text: str
    start: int | None
    end: int | None


def has_chat_template(tokenizer: Any) -> bool:
    return bool(getattr(tokenizer, "has_chat_template", False)) or bool(
        getattr(tokenizer, "chat_template", None)
    )


def chat_prompt(tokenizer: Any, messages: list[dict[str, str]]) -> str:
    """会話をモデルのチャットの型に包み、応答を書き始める直前までの文字列にする。"""
    if not has_chat_template(tokenizer):
        raise UnsupportedError("このモデルはチャットの型（chat template）を持っていません")
    text = tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
    return str(text)


def encode_prompt(
    tokenizer: Any, prompt: str, chat_template: bool, limit: int | None = MAX_PROMPT_TOKENS
) -> list[int]:
    """プロンプトをトークン ID の列にする。`chat_template` なら、ユーザーの発言として包む。"""
    if chat_template:
        text = chat_prompt(tokenizer, [{"role": "user", "content": prompt}])
        ids = list(tokenizer.encode(text, add_special_tokens=False))
    else:
        ids = list(tokenizer.encode(prompt))
    if not ids:
        raise BadRequestError("プロンプトが空です")
    if limit is not None and len(ids) > limit:
        raise BadRequestError(
            f"プロンプトが長すぎます（{len(ids)} トークン。{limit} トークンまでにしてください）"
        )
    return [int(token) for token in ids]


_TEXTS: weakref.WeakKeyDictionary[Any, dict[int, str]] = weakref.WeakKeyDictionary()
"""トークナイザごとの、ID → 文字列の覚え書き。logit lens などで同じ ID を何万回も引くため"""


def token_text(tokenizer: Any, token: int) -> str:
    """1 つのトークンを文字列にする。文字の途中で切れた断片は U+FFFD を含む。"""
    try:
        texts = _TEXTS.setdefault(tokenizer, {})
    except TypeError:
        return str(tokenizer.decode([token]))
    text = texts.get(token)
    if text is None:
        text = str(tokenizer.decode([token]))
        texts[token] = text
    return text


def tokenize_with_offsets(tokenizer: Any, text: str) -> list[TokenSpan]:
    """文字列をトークンに区切り、各トークンの位置（Python の添字）を付ける。

    位置が決まらない断片（1 文字を複数のトークンに分けたものなど）は `start`、`end` を None にする。
    """
    backend: Any = getattr(tokenizer, "_tokenizer", tokenizer)
    try:
        encoded = backend(text, add_special_tokens=False, return_offsets_mapping=True)
        ids = [int(token) for token in encoded["input_ids"]]
        offsets: list[tuple[int, int] | None] = [
            (int(start), int(end)) for start, end in encoded["offset_mapping"]
        ]
    except (NotImplementedError, TypeError, KeyError, ValueError):
        ids = [int(token) for token in tokenizer.encode(text, add_special_tokens=False)]
        offsets = [None] * len(ids)

    spans: list[TokenSpan] = []
    for token, offset in zip(ids, offsets, strict=True):
        piece = token_text(tokenizer, token)
        start: int | None = None
        end: int | None = None
        if offset is not None and REPLACEMENT_CHARACTER not in piece:
            begin, finish = offset
            if 0 <= begin < finish <= len(text):
                start, end = begin, finish
        spans.append(TokenSpan(id=token, text=piece, start=start, end=end))
    return spans
