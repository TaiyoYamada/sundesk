"""グラフの分析。networkx の PageRank（重み付き）と Louvain 法のコミュニティ検出。

networkx には型の情報がないので、呼び出しはこのモジュールに閉じ込める。
"""

from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any

import networkx as nx

LOUVAIN_SEED = 42


@dataclass(frozen=True)
class Analysis:
    pagerank: list[float]
    community: list[int]


def analyze(node_count: int, edges: Iterable[tuple[int, int, float]]) -> Analysis:
    """無向の重み付きグラフとして分析する。同じ組の線は重みを足し合わせる。

    コミュニティの番号は、大きい順（同じ大きさなら、最小の点の番号が小さい順）に 0 から振る。
    """
    if node_count == 0:
        return Analysis(pagerank=[], community=[])
    graph: Any = nx.Graph()  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType]
    graph.add_nodes_from(range(node_count))
    for source, target, weight in edges:
        if source == target or weight <= 0:
            continue
        if graph.has_edge(source, target):
            graph[source][target]["weight"] += weight
        else:
            graph.add_edge(source, target, weight=weight)

    ranks: dict[int, float] = nx.pagerank(graph, weight="weight")  # pyright: ignore[reportUnknownMemberType]
    groups: list[set[int]] = nx.community.louvain_communities(  # pyright: ignore[reportUnknownMemberType]
        graph, weight="weight", seed=LOUVAIN_SEED
    )
    ordered = sorted(groups, key=lambda group: (-len(group), min(group)))
    community = [0] * node_count
    for number, group in enumerate(ordered):
        for node in group:
            community[node] = number
    return Analysis(
        pagerank=[float(ranks[node]) for node in range(node_count)], community=community
    )
