"""知識グラフの組み立てのテスト。本物の SudachiPy を使う。"""

from typing import Any

import numpy as np
import pytest
from numpy.typing import NDArray

from sundesk_engine.graph.analysis import analyze
from sundesk_engine.graph.builder import build_graph
from sundesk_engine.graph.schemas import BuildRequest, BuildResponse
from sundesk_engine.nlp.terms import TermExtractor, normalize

NOTES: list[dict[str, Any]] = [
    {
        "path": "数学/固有値.md",
        "title": "固有値",
        "links": ["数学/線形代数.md", "数学/存在しない.md"],
        "chunks": [
            {
                "id": "数学/固有値.md#0",
                "heading_path": ["固有値", "定義"],
                "text": "固有値とは、線形変換で向きが変わらないベクトルの伸縮率である。"
                "固有値と固有ベクトルは線形代数の基本である。",
            },
            {
                "id": "数学/固有値.md#1",
                "heading_path": ["固有値", "固有値分解"],
                "text": "固有値分解は行列分解の一種である。"
                "固有値分解では固有値と固有ベクトルを使う。",
            },
        ],
    },
    {
        "path": "数学/線形代数.md",
        "title": "線形代数",
        "links": [],
        "chunks": [
            {
                "id": "数学/線形代数.md#0",
                "heading_path": ["線形代数"],
                "text": "線形代数はベクトルと行列を扱う数学の分野である。"
                "Singular Value Decomposition（SVD）も行列分解の一つである。",
            },
            {
                "id": "数学/線形代数.md#1",
                "heading_path": ["線形代数", "行列"],
                "text": "行列は数を長方形に並べたもののことである。"
                "PageRankは行列の固有ベクトルを使う。",
            },
        ],
    },
    {
        "path": "料理/カレー.md",
        "title": "カレー",
        "links": [],
        "chunks": [
            {
                "id": "料理/カレー.md#0",
                "heading_path": ["カレー"],
                "text": "カレーは玉ねぎと人参を煮込む料理である。玉ねぎを炒める。",
            },
            {
                "id": "料理/カレー.md#1",
                "heading_path": ["カレー", "材料"],
                "text": "玉ねぎと人参とスパイスを用意する。人参は大きめに切る。",
            },
        ],
    },
]


def build(**options: Any) -> BuildResponse:
    merged = {"max_concepts": 100, "min_frequency": 1, "min_cooccurrence": 1} | options
    return build_graph(BuildRequest.model_validate({"notes": NOTES, "options": merged}))


def labels(response: BuildResponse) -> dict[str, int]:
    return {concept.label: concept.id for concept in response.concepts}


def relations(response: BuildResponse, kind: str) -> set[tuple[str, str]]:
    names = {concept.id: concept.label for concept in response.concepts}
    return {
        (names[relation.source], names[relation.target])
        for relation in response.relations
        if relation.kind == kind
    }


@pytest.fixture(scope="module")
def graph() -> BuildResponse:
    return build()


def test_normalize_folds_width_and_latin_case() -> None:
    assert normalize("ＰａｇｅＲａｎｋ") == "pagerank"
    assert normalize("Singular  Value\nDecomposition") == "singular value decomposition"
    assert normalize("ＡＩ　モデル") == "ai モデル"
    # 英字以外の大文字小文字は変えない
    assert normalize("Ω") == "Ω"


def test_extractor_finds_noun_runs_and_nested_terms() -> None:
    occurrences = TermExtractor().occurrences("固有値分解はSingular Value Decompositionに近い。")
    keys = {occurrence.key for occurrence in occurrences}

    assert {"固有値分解", "固有値", "分解", "singular value decomposition"} <= keys
    compound = next(occurrence for occurrence in occurrences if occurrence.key == "固有値分解")
    assert compound.start == 0
    assert compound.end == 5
    assert set(compound.children) == {"固有値", "分解"}


def test_extractor_skips_function_words() -> None:
    keys = {
        occurrence.key for occurrence in TermExtractor().occurrences("そのことは、ために行う。")
    }

    assert "こと" not in keys
    assert "ため" not in keys


def test_titles_are_always_concepts() -> None:
    response = build(min_frequency=100)

    assert set(labels(response)) == {"固有値", "線形代数", "カレー"}


def test_concepts_are_sorted_by_score_and_numbered(graph: BuildResponse) -> None:
    assert [concept.id for concept in graph.concepts] == list(range(len(graph.concepts)))
    scores = [concept.score for concept in graph.concepts]
    assert scores == sorted(scores, reverse=True)
    names = labels(graph)
    assert {"固有値", "固有値分解", "行列分解", "固有ベクトル", "玉ねぎ", "人参"} <= set(names)
    eigen = graph.concepts[names["固有値"]]
    assert eigen.normalized == "固有値"
    assert eigen.frequency == 5


def test_mentions_count_occurrences_per_chunk(graph: BuildResponse) -> None:
    names = labels(graph)
    mentions = {(mention.concept, mention.chunk): mention.count for mention in graph.mentions}

    assert mentions[(names["固有値"], "数学/固有値.md#0")] == 2
    assert mentions[(names["固有値分解"], "数学/固有値.md#1")] == 2
    assert (names["カレー"], "数学/固有値.md#0") not in mentions


def test_contains_links_compounds_to_parts(graph: BuildResponse) -> None:
    contains = relations(graph, "contains")

    assert ("固有値分解", "固有値") in contains
    assert ("固有ベクトル", "ベクトル") in contains
    assert ("行列分解", "行列") in contains


def test_definition_and_is_a_patterns(graph: BuildResponse) -> None:
    assert ("固有値", "伸縮率") in relations(graph, "definition")
    assert ("行列", "もの") not in relations(graph, "definition")
    is_a = relations(graph, "is_a")
    assert ("固有値分解", "行列分解") in is_a
    assert ("SVD", "行列分解") in is_a


def test_link_connects_titles_of_existing_notes(graph: BuildResponse) -> None:
    assert relations(graph, "link") == {("固有値", "線形代数")}


def test_hierarchy_points_from_heading_to_section_terms(graph: BuildResponse) -> None:
    hierarchy = relations(graph, "hierarchy")

    assert ("固有値分解", "行列分解") in hierarchy
    assert ("カレー", "玉ねぎ") in hierarchy
    # 見出しの概念の部分（固有値分解 → 分解）には引かない
    assert ("固有値分解", "分解") not in hierarchy


def test_cooccurrence_keeps_only_positive_pmi(graph: BuildResponse) -> None:
    cooccurrence = [relation for relation in graph.relations if relation.kind == "cooccurrence"]
    names = {concept.id: concept.label for concept in graph.concepts}
    pairs = {(names[r.source], names[r.target]) for r in cooccurrence}
    pairs |= {(b, a) for a, b in pairs}

    assert cooccurrence
    assert all(relation.weight > 0 for relation in cooccurrence)
    assert all(relation.source < relation.target for relation in cooccurrence)
    assert ("玉ねぎ", "人参") in pairs
    # 複合語とその部分の組は、共起として数えない
    assert ("固有値分解", "固有値") not in pairs


def test_cooccurrence_threshold_filters_rare_pairs() -> None:
    strict = build(min_cooccurrence=2)
    names = {concept.id: concept.label for concept in strict.concepts}
    pairs = {
        frozenset((names[r.source], names[r.target]))
        for r in strict.relations
        if r.kind == "cooccurrence"
    }

    assert frozenset(("玉ねぎ", "人参")) in pairs
    assert frozenset(("伸縮率", "線形変換")) not in pairs


def test_evidence_refers_to_chunks(graph: BuildResponse) -> None:
    chunk_ids = {chunk["id"] for note in NOTES for chunk in note["chunks"]}

    assert all(relation.evidence in chunk_ids for relation in graph.relations)


def test_pagerank_and_communities_are_deterministic(graph: BuildResponse) -> None:
    again = build()

    assert graph == again
    assert abs(sum(concept.pagerank for concept in graph.concepts) - 1.0) < 1e-3
    names = labels(graph)
    by_id = {concept.id: concept for concept in graph.concepts}
    # 数学の話と料理の話は、別のコミュニティになる
    assert by_id[names["玉ねぎ"]].community == by_id[names["人参"]].community
    assert by_id[names["玉ねぎ"]].community != by_id[names["固有値分解"]].community


def test_max_concepts_limits_the_number() -> None:
    response = build(max_concepts=5)

    assert len(response.concepts) == 5
    assert {"固有値", "線形代数", "カレー"} <= set(labels(response))


def test_similarity_uses_embeddings() -> None:
    request = BuildRequest.model_validate(
        {
            "notes": NOTES,
            "options": {"max_concepts": 100, "min_frequency": 1, "similarity": True},
        }
    )

    def embed(texts: list[str]) -> NDArray[np.float32]:
        # 「玉ねぎ」と「人参」だけを同じ向きにする
        rows = np.eye(len(texts), dtype=np.float32)
        a, b = texts.index("玉ねぎ"), texts.index("人参")
        rows[b] = rows[a]
        return rows

    response = build_graph(request, embed)

    similar = relations(response, "similar")
    assert similar in ({("玉ねぎ", "人参")}, {("人参", "玉ねぎ")})
    assert all(r.weight == pytest.approx(1.0) for r in response.relations if r.kind == "similar")


def test_empty_request() -> None:
    response = build_graph(BuildRequest(notes=[]))

    assert response == BuildResponse(concepts=[], mentions=[], relations=[])


def test_analyze_orders_communities_by_size() -> None:
    result = analyze(5, [(0, 1, 1.0), (1, 2, 1.0), (0, 2, 1.0), (3, 4, 1.0)])

    assert result.community[:3] == [0, 0, 0]
    assert result.community[3:] == [1, 1]
    assert len(result.pagerank) == 5


def test_extractor_ignores_urls_and_english_function_words() -> None:
    text = "詳しくは https://example.org/docs を参照（Smith et al. 2020）。AI と CMA-ES を使う。"
    keys = {occurrence.key for occurrence in TermExtractor().occurrences(text)}

    assert not keys & {"https", "example", "org", "docs", "et", "al", "et al"}
    assert {"ai", "cma-es", "smith"} <= keys


def test_is_a_in_the_middle_of_a_sentence() -> None:
    notes = [
        {
            "path": "量子/QAOA.md",
            "title": "QAOA",
            "chunks": [
                {"id": "q#0", "text": "**QAOA は VQE の一種**と見なせる。VQE は変分法である。"},
            ],
        }
    ]
    response = build_graph(
        BuildRequest.model_validate({"notes": notes, "options": {"min_frequency": 1}})
    )

    assert relations(response, "is_a") == {("QAOA", "VQE")}
