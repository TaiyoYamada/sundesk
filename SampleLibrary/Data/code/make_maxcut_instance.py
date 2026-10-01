"""Data/instances/ の Max-Cut のインスタンスを作り、全探索で最適値を求める。

30 頂点、辺の確率 0.4、重みは 1〜10 の整数（一様）。頂点 0 を片側に固定して 2^29 通りを調べる。
"""

from __future__ import annotations

import time

import numpy as np
from maxcut import INSTANCE, MaxCut, dumps, load, write_qubo

SEED = 2026
NODES = 30
EDGE_PROBABILITY = 0.4
CHUNK = 1 << 18


def generate() -> list[tuple[int, int, int]]:
    rng = np.random.default_rng(SEED)
    edges = []
    for i in range(NODES):
        for j in range(i + 1, NODES):
            if rng.random() < EDGE_PROBABILITY:
                edges.append((i, j, int(rng.integers(1, 11))))
    return edges


def brute_force(instance: MaxCut) -> tuple[float, list[int], int]:
    """頂点 0 を 0 に固定して、残りの 29 頂点のすべての割り当てを調べる。"""
    n = instance.n
    weights = instance.weights.astype(np.float32)
    bits = np.arange(n - 1, dtype=np.int64)
    best, best_x, count = -1.0, None, 0
    for start in range(0, 1 << (n - 1), CHUNK):
        index = np.arange(start, start + CHUNK, dtype=np.int64)
        x = np.zeros((CHUNK, n), dtype=np.float32)
        x[:, 1:] = (index[:, None] >> bits) & 1
        cuts = ((x @ weights) * (1 - x)).sum(axis=1)
        top = float(cuts.max())
        if top > best:
            best, best_x = top, x[int(np.argmax(cuts))].astype(int).tolist()
            count = int(np.sum(cuts == top))
        elif top == best:
            count += int(np.sum(cuts == top))
    assert best_x is not None
    return best, best_x, count


def main() -> None:
    edges = generate()
    weights = np.zeros((NODES, NODES))
    for i, j, w in edges:
        weights[i, j] = weights[j, i] = w
    start = time.perf_counter()
    cut, partition, count = brute_force(MaxCut("maxcut-w30", weights, 0))
    elapsed = time.perf_counter() - start
    data = {
        "name": "maxcut-w30",
        "problem": "weighted Max-Cut",
        "nodes": NODES,
        "edge_probability": EDGE_PROBABILITY,
        "weights": "integer uniform in [1, 10]",
        "seed": SEED,
        "total_weight": int(sum(w for _, _, w in edges)),
        "edges": [list(edge) for edge in edges],
        "optimum": {
            "cut": int(cut),
            "partition": partition,
            "optimal_assignments": count,  # 頂点 0 を 0 に固定したときの数（反転を除く）
            "method": "brute force over 2^29 assignments (vertex 0 fixed)",
            "seconds": round(elapsed, 1),
        },
    }
    INSTANCE.parent.mkdir(parents=True, exist_ok=True)
    INSTANCE.write_text(dumps(data), encoding="utf-8")
    instance = load()
    assert instance.cut(np.array(partition)) == cut
    x = np.array(partition)
    assert x @ instance.qubo() @ x == -cut
    write_qubo(instance)
    print(f"{len(edges)} 辺、最大カット {cut:.0f}（{count} 通り）、{elapsed:.1f} 秒")


if __name__ == "__main__":
    main()
