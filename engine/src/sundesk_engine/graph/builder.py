"""ノートから知識グラフ（概念、出現、関係）を作る。

1. SudachiPy で名詞の連続（と英字の語）を候補にし、C-value と出現数で重要度を付ける
2. 上位の候補とノートのタイトルを概念にする
3. 共起（PMI）、見出し、定義・上位下位の文型、リンク、複合語、埋め込みの類似から関係を作る
4. PageRank とコミュニティを計算する
"""

import math
import re
from collections import Counter, defaultdict
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field

import numpy as np
from numpy.typing import NDArray

from sundesk_engine.graph.analysis import analyze
from sundesk_engine.graph.schemas import (
    BuildRequest,
    BuildResponse,
    ConceptOut,
    MentionOut,
    RelationKind,
    RelationOut,
)
from sundesk_engine.nlp.terms import Occurrence, TermExtractor, normalize, sentences

type Embed = Callable[[list[str]], NDArray[np.float32]]

MAX_CONCEPTS_PER_CHUNK_FOR_COOCCURRENCE = 40
"""共起を数えるときに使う、1 つのチャンクの概念の数の上限（出現数の多い順）"""
MAX_COOCCURRENCE_PER_CONCEPT = 20
"""1 つの概念から出す共起の線の数の上限（重みの大きい順）"""
MAX_HIERARCHY_TARGETS = 5
"""見出しの概念から線を引く、本文の概念の数"""
MAX_SIMILAR_PER_CONCEPT = 5

# 文の途中に現れてもよい（「A は B の一種と見なせる」など）。A は最初の「は」の直前まで
_IS_A = re.compile(
    r"(?P<a>.+?)\s*(?:とは|は|も)[、,，]?\s*(?P<b>.+?)\s*の(?:一種|1種|１種|一つ|ひとつ|1つ|１つ)"
)
_COPULA_WORDS = "である|であり|です|をいう|をいいます|を言う|を指す|を指します"
_COPULA = f"(?:{_COPULA_WORDS})"
_DEFINITIONS = (
    re.compile(r"(?P<a>.+?)\s*とは[、,，]?\s*(?P<b>.+?)(?:のこと)?" + _COPULA),
    # 「だ」は語の中にも現れる（「ただし」「だけ」）ので、文の終わりだけで見る
    re.compile(r"(?P<a>.+?)\s*とは[、,，]?\s*(?P<b>.+?)(?:のこと)?だ$"),
    re.compile(r"(?P<a>.+?)\s*とは[、,，]?\s*(?P<b>.+?)のこと$"),
    re.compile(r"(?P<a>.+?)\s*は[、,，]?\s*(?P<b>.+?)のこと(?:" + _COPULA_WORDS + "|だ|$)"),
)
_SENTENCE_END = "。．！？!?.\n\r\t "


@dataclass
class _Candidate:
    length: int
    frequency: int = 0
    surfaces: Counter[str] = field(default_factory=Counter[str])
    chunks: Counter[int] = field(default_factory=Counter[int])


@dataclass(frozen=True)
class _Chunk:
    id: str
    note: int
    heading_path: tuple[str, ...]
    text: str


@dataclass
class _Relations:
    weights: dict[tuple[RelationKind, int, int], float] = field(
        default_factory=dict[tuple[RelationKind, int, int], float]
    )
    evidence: dict[tuple[RelationKind, int, int], str] = field(
        default_factory=dict[tuple[RelationKind, int, int], str]
    )

    def add(
        self, kind: RelationKind, source: int, target: int, weight: float, evidence: str
    ) -> None:
        if source == target:
            return
        key = (kind, source, target)
        self.weights[key] = self.weights.get(key, 0.0) + weight
        self.evidence.setdefault(key, evidence)

    def has_pair(self, kind: RelationKind, a: int, b: int) -> bool:
        return (kind, a, b) in self.weights or (kind, b, a) in self.weights


def _c_value(candidate: _Candidate, parents: set[str], candidates: dict[str, _Candidate]) -> float:
    weight = math.log2(1 + candidate.length)
    if not parents:
        return weight * candidate.frequency
    nested = sum(candidates[parent].frequency for parent in parents) / len(parents)
    return weight * (candidate.frequency - nested)


def _score(c_value: float, document_frequency: int) -> float:
    return c_value * math.log2(1 + document_frequency)


def _span_end(text: str, start: int, end: int) -> int:
    """範囲の終わりから、空白、読点、閉じ括弧を除いた位置。"""
    while end > start and text[end - 1] in " 　、,，\t）)」』】*_":
        end -= 1
    return end


class GraphBuilder:
    def __init__(self, request: BuildRequest, embed: Embed | None = None) -> None:
        self.request = request
        self.options = request.options
        self.embed = embed
        self.extractor = TermExtractor()
        self.chunks = [
            _Chunk(chunk.id, index, tuple(chunk.heading_path), chunk.text)
            for index, note in enumerate(request.notes)
            for chunk in note.chunks
        ]

    def build(self) -> BuildResponse:
        occurrences = [self.extractor.occurrences(chunk.text) for chunk in self.chunks]
        candidates, nested = self._collect(occurrences)
        titles = self._titles(nested)
        parents: defaultdict[str, set[str]] = defaultdict(set)
        for parent, child in nested:
            if parent in candidates:
                parents[child].add(parent)

        chunk_counts = self._title_counts(titles, candidates)
        scores: dict[str, float] = {}
        for key, candidate in candidates.items():
            scores[key] = _score(
                _c_value(candidate, parents[key], candidates), len(candidate.chunks)
            )
        for key in titles:
            if key not in candidates:
                total = sum(chunk_counts[key].values())
                scores[key] = _score(float(total), len(chunk_counts[key]))
            scores[key] = max(scores[key], 0.0)

        eligible = sorted(
            (
                key
                for key, candidate in candidates.items()
                if key not in titles
                and candidate.frequency >= self.options.min_frequency
                and scores[key] > 0
            ),
            key=lambda key: (-scores[key], key),
        )
        room = max(0, self.options.max_concepts - len(titles))
        chosen = sorted([*titles, *eligible[:room]], key=lambda key: (-scores[key], key))
        ids = {key: index for index, key in enumerate(chosen)}

        per_chunk: list[dict[int, int]] = []
        for index in range(len(self.chunks)):
            counts: dict[int, int] = {}
            for key, concept in ids.items():
                if key in titles:
                    count = chunk_counts[key].get(index, 0)
                else:
                    count = candidates[key].chunks.get(index, 0)
                if count > 0:
                    counts[concept] = count
            per_chunk.append(counts)

        frequency = [0] * len(chosen)
        first_chunk: list[str | None] = [None] * len(chosen)
        for index, counts in enumerate(per_chunk):
            for concept, count in counts.items():
                frequency[concept] += count
                if first_chunk[concept] is None:
                    first_chunk[concept] = self.chunks[index].id
        fallback = {
            ids[key]: self.request.notes[note].path for key, (_label, note) in titles.items()
        }
        evidence = [first or fallback.get(concept, "") for concept, first in enumerate(first_chunk)]

        labels = [
            titles[key][0] if key in titles else candidates[key].surfaces.most_common(1)[0][0]
            for key in chosen
        ]

        relations = _Relations()
        self._contains(relations, nested, ids, evidence)
        self._cooccurrence(relations, per_chunk, scores, chosen, nested)
        self._hierarchy(relations, per_chunk, ids, scores, chosen)
        self._patterns(relations, occurrences, ids)
        self._links(relations, ids)
        if self.options.similarity and self.embed is not None:
            self._similar(relations, labels, evidence)

        edges = [
            (source, target, weight) for (_k, source, target), weight in relations.weights.items()
        ]
        analysis = analyze(len(chosen), edges)

        concepts = [
            ConceptOut(
                id=concept,
                label=labels[concept],
                normalized=key,
                score=round(scores[key], 4),
                frequency=frequency[concept],
                pagerank=round(analysis.pagerank[concept], 6),
                community=analysis.community[concept],
            )
            for concept, key in enumerate(chosen)
        ]
        mentions = [
            MentionOut(concept=concept, chunk=self.chunks[index].id, count=count)
            for index, counts in enumerate(per_chunk)
            for concept, count in sorted(counts.items())
        ]
        kind_order: dict[RelationKind, int] = {
            "cooccurrence": 0,
            "hierarchy": 1,
            "definition": 2,
            "is_a": 3,
            "link": 4,
            "contains": 5,
            "similar": 6,
        }
        relation_list = [
            RelationOut(
                source=source,
                target=target,
                kind=kind,
                weight=round(weight, 4),
                evidence=relations.evidence[(kind, source, target)],
            )
            for (kind, source, target), weight in sorted(
                relations.weights.items(), key=lambda item: (kind_order[item[0][0]], item[0][1:])
            )
        ]
        return BuildResponse(concepts=concepts, mentions=mentions, relations=relation_list)

    # MARK: - 候補

    def _collect(
        self, occurrences: list[list[Occurrence]]
    ) -> tuple[dict[str, _Candidate], set[tuple[str, str]]]:
        candidates: dict[str, _Candidate] = {}
        nested: set[tuple[str, str]] = set()
        for index, found in enumerate(occurrences):
            for occurrence in found:
                candidate = candidates.setdefault(occurrence.key, _Candidate(occurrence.length))
                candidate.frequency += 1
                candidate.surfaces[occurrence.surface] += 1
                candidate.chunks[index] += 1
                nested.update((occurrence.key, child) for child in occurrence.children)
        return candidates, nested

    def _titles(self, nested: set[tuple[str, str]]) -> dict[str, tuple[str, int]]:
        """タイトルの正規化した形 → (ラベル, ノートの番号)。タイトルに含まれる候補も記録する。"""
        titles: dict[str, tuple[str, int]] = {}
        for index, note in enumerate(self.request.notes):
            key = normalize(note.title)
            if not key or key in titles:
                continue
            titles[key] = (note.title.strip(), index)
            for occurrence in self.extractor.occurrences(note.title):
                if occurrence.key != key:
                    nested.add((key, occurrence.key))
        return titles

    def _title_counts(
        self, titles: dict[str, tuple[str, int]], candidates: dict[str, _Candidate]
    ) -> dict[str, Counter[int]]:
        """タイトルの概念がチャンクに出る回数。形態素の区切りに関係なく、文字列として数える。"""
        normalized = [normalize(chunk.text) for chunk in self.chunks]
        counts: dict[str, Counter[int]] = {}
        for key in titles:
            counter: Counter[int] = Counter()
            known = candidates[key].chunks if key in candidates else Counter[int]()
            for index, text in enumerate(normalized):
                count = max(text.count(key), known.get(index, 0))
                if count:
                    counter[index] = count
            counts[key] = counter
        return counts

    # MARK: - 関係

    def _contains(
        self,
        relations: _Relations,
        nested: set[tuple[str, str]],
        ids: dict[str, int],
        evidence: list[str],
    ) -> None:
        for parent, child in sorted(nested):
            if parent in ids and child in ids and parent != child:
                source = ids[parent]
                key: tuple[RelationKind, int, int] = ("contains", source, ids[child])
                if key not in relations.weights:
                    relations.add("contains", source, ids[child], 1.0, evidence[source])

    def _cooccurrence(
        self,
        relations: _Relations,
        per_chunk: list[dict[int, int]],
        scores: dict[str, float],
        chosen: list[str],
        nested: set[tuple[str, str]],
    ) -> None:
        total_chunks = len(self.chunks)
        document_frequency: Counter[int] = Counter()
        pair_counts: Counter[tuple[int, int]] = Counter()
        first: dict[tuple[int, int], int] = {}
        for index, counts in enumerate(per_chunk):
            document_frequency.update(counts.keys())
            present = sorted(counts, key=lambda c: (-counts[c], -scores[chosen[c]], c))
            present = sorted(present[:MAX_CONCEPTS_PER_CHUNK_FOR_COOCCURRENCE])
            for i, a in enumerate(present):
                for b in present[i + 1 :]:
                    pair_counts[(a, b)] += 1
                    first.setdefault((a, b), index)

        candidates: list[tuple[int, int, float]] = []
        for (a, b), together in pair_counts.items():
            if together < self.options.min_cooccurrence:
                continue
            key_a, key_b = chosen[a], chosen[b]
            if (
                key_a in key_b
                or key_b in key_a
                or (key_a, key_b) in nested
                or (key_b, key_a) in nested
            ):
                # 複合語とその部分は、同じところに出るのが当たり前なので数えない
                continue
            pmi = math.log(
                together * total_chunks / (document_frequency[a] * document_frequency[b])
            )
            if pmi <= 0:
                continue
            candidates.append((a, b, pmi * math.log(1 + together)))

        best: defaultdict[int, list[tuple[float, int, int]]] = defaultdict(list)
        for a, b, weight in candidates:
            best[a].append((weight, a, b))
            best[b].append((weight, a, b))
        kept: set[tuple[int, int]] = set()
        for edges in best.values():
            edges.sort(key=lambda edge: (-edge[0], edge[1], edge[2]))
            kept.update((a, b) for _w, a, b in edges[:MAX_COOCCURRENCE_PER_CONCEPT])
        for a, b, weight in candidates:
            if (a, b) in kept:
                relations.add("cooccurrence", a, b, weight, self.chunks[first[(a, b)]].id)

    def _heading_concepts(self, heading: str, ids: dict[str, int]) -> set[int]:
        """見出しの概念。見出し全体が概念ならそれ、でなければ見出しに含まれる最長の概念。"""
        key = normalize(heading)
        if key in ids:
            return {ids[key]}
        found = [
            occurrence
            for occurrence in self.extractor.occurrences(heading)
            if occurrence.key in ids
        ]
        maximal = [
            occurrence
            for occurrence in found
            if not any(
                other is not occurrence
                and other.start <= occurrence.start
                and occurrence.end <= other.end
                and (other.end - other.start) > (occurrence.end - occurrence.start)
                for other in found
            )
        ]
        return {ids[occurrence.key] for occurrence in maximal}

    def _hierarchy(
        self,
        relations: _Relations,
        per_chunk: list[dict[int, int]],
        ids: dict[str, int],
        scores: dict[str, float],
        chosen: list[str],
    ) -> None:
        cache: dict[str, set[int]] = {}
        for index, chunk in enumerate(self.chunks):
            if not chunk.heading_path:
                continue
            heading = chunk.heading_path[-1]
            if heading not in cache:
                cache[heading] = self._heading_concepts(heading, ids)
            sources = cache[heading]
            if not sources:
                continue
            counts = per_chunk[index]
            targets = sorted(
                (
                    concept
                    for concept in counts
                    if concept not in sources
                    and not any(chosen[concept] in chosen[source] for source in sources)
                ),
                key=lambda concept: (-scores[chosen[concept]], -counts[concept], concept),
            )[:MAX_HIERARCHY_TARGETS]
            for source in sorted(sources):
                for target in targets:
                    relations.add("hierarchy", source, target, float(counts[target]), chunk.id)

    def _concept_ending_at(
        self, text: str, start: int, end: int, found: list[Occurrence], ids: dict[str, int]
    ) -> int | None:
        end = _span_end(text, start, end)
        if end <= start:
            return None
        whole = normalize(text[start:end])
        if whole in ids:
            return ids[whole]
        matches = [
            occurrence
            for occurrence in found
            if occurrence.end == end and occurrence.start >= start and occurrence.key in ids
        ]
        if not matches:
            return None
        longest = min(matches, key=lambda occurrence: occurrence.start)
        return ids[longest.key]

    def _patterns(
        self, relations: _Relations, occurrences: list[list[Occurrence]], ids: dict[str, int]
    ) -> None:
        for index, chunk in enumerate(self.chunks):
            found = occurrences[index]
            for offset, sentence in sentences(chunk.text):
                body = sentence.rstrip(_SENTENCE_END)
                kind: RelationKind = "is_a"
                match = _IS_A.search(body)
                if match is None:
                    kind = "definition"
                    match = next(
                        (m for pattern in _DEFINITIONS if (m := pattern.search(body))), None
                    )
                if match is None:
                    continue
                a_start, a_end = match.span("a")
                b_start, b_end = match.span("b")
                source = self._concept_ending_at(
                    chunk.text, offset + a_start, offset + a_end, found, ids
                )
                target = self._concept_ending_at(
                    chunk.text, offset + b_start, offset + b_end, found, ids
                )
                if source is not None and target is not None:
                    relations.add(kind, source, target, 1.0, chunk.id)

    def _links(self, relations: _Relations, ids: dict[str, int]) -> None:
        by_path = {note.path: normalize(note.title) for note in self.request.notes}
        for note in self.request.notes:
            source_key = normalize(note.title)
            if source_key not in ids:
                continue
            evidence = note.chunks[0].id if note.chunks else note.path
            for link in note.links:
                target_key = by_path.get(link)
                if target_key is not None and target_key in ids:
                    relations.add("link", ids[source_key], ids[target_key], 1.0, evidence)

    def _similar(self, relations: _Relations, labels: Sequence[str], evidence: list[str]) -> None:
        assert self.embed is not None  # noqa: S101 - 呼ぶ側で確かめている
        if len(labels) < 2:
            return
        vectors = np.asarray(self.embed(list(labels)), dtype=np.float32)
        similarity = vectors @ vectors.T
        np.fill_diagonal(similarity, -np.inf)
        threshold = self.options.similarity_threshold
        for a in range(len(labels)):
            row = similarity[a]
            neighbors = np.argsort(-row, kind="stable")[:MAX_SIMILAR_PER_CONCEPT]
            for b in neighbors.tolist():
                value = float(row[b])
                if value < threshold:
                    break
                source, target = (a, b) if a < b else (b, a)
                if ("similar", source, target) in relations.weights:
                    continue
                if relations.has_pair("contains", source, target):
                    continue
                relations.add("similar", source, target, value, evidence[source])


def build_graph(request: BuildRequest, embed: Embed | None = None) -> BuildResponse:
    """知識グラフを作る。`similarity` が true なら、`embed` で概念の名前を埋め込む。"""
    return GraphBuilder(request, embed).build()
