"""重みつき Max-Cut のインスタンスと、その QUBO（イジング）への書き換え。

カットの重み cut(x) = Σ_{i<j} w_ij (x_i + x_j - 2 x_i x_j)（x_i ∈ {0, 1}）を最大にする。
QUBO では最小化に合わせて符号を反転し、xᵀ Q x（Q は上三角）= -cut(x) とする（Lucas 2014 の Max-Cut の書き換え）。
イジング（s_i = 1 - 2 x_i）では E(s) = Σ_{i<j} w_ij s_i s_j を最小にすることと同じで、
cut = (W - E) / 2（W は重みの合計）になる。
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np

LIBRARY = Path(__file__).resolve().parents[2]
INSTANCE = LIBRARY / "Data/instances/maxcut-w30.json"


@dataclass
class MaxCut:
    name: str
    weights: np.ndarray  # 対称、対角は 0
    optimum: float

    @property
    def n(self) -> int:
        return len(self.weights)

    @property
    def total_weight(self) -> float:
        return float(np.triu(self.weights).sum())

    def cut(self, x: np.ndarray) -> np.ndarray:
        """x は (…, n) の 0/1 の配列。最後の軸ごとにカットの重みを返す。"""
        x = np.asarray(x, dtype=float)
        return np.einsum("...i,ij,...j->...", x, self.weights, 1 - x)

    def ising_energy(self, s: np.ndarray) -> np.ndarray:
        """s は (…, n) の ±1 の配列。E = Σ_{i<j} w_ij s_i s_j。"""
        s = np.asarray(s, dtype=float)
        return np.einsum("...i,ij,...j->...", s, self.weights, s) / 2

    def qubo(self) -> np.ndarray:
        """xᵀ Q x = -cut(x) となる上三角の Q。"""
        q = np.triu(2 * self.weights, k=1)
        np.fill_diagonal(q, -self.weights.sum(axis=1))
        return q


def dumps(data: object) -> str:
    """読みやすい JSON。数だけの配列（辺やカットの割り当て）は 1 行にまとめる。"""
    text = json.dumps(data, ensure_ascii=False, indent=2)
    return (
        re.sub(r"\[\s*([-\d.,\s]+?)\s*\]", lambda m: "[" + re.sub(r"\s+", " ", m[1]) + "]", text)
        + "\n"
    )


def load(path: Path = INSTANCE) -> MaxCut:
    data = json.loads(path.read_text(encoding="utf-8"))
    n = data["nodes"]
    weights = np.zeros((n, n))
    for i, j, w in data["edges"]:
        weights[i, j] = weights[j, i] = w
    return MaxCut(data["name"], weights, float(data["optimum"]["cut"]))


def write_qubo(instance: MaxCut, path: Path | None = None) -> Path:
    """QUBO の形（上三角の Q の非零要素）を JSON に書く。"""
    path = path or INSTANCE.with_name(f"{instance.name}-qubo.json")
    q = instance.qubo()
    entries = [[int(i), int(j), int(q[i, j])] for i, j in zip(*np.nonzero(q), strict=True)]
    data = {
        "name": f"{instance.name}-qubo",
        "source": f"Data/instances/{instance.name}.json",
        "variables": instance.n,
        "sense": "minimize",
        "form": "x^T Q x, x in {0,1}^n, Q upper triangular (i <= j)",
        "offset": 0,
        "q": entries,
        "optimum": {"energy": -int(instance.optimum)},
        "note": "xᵀ Q x = -cut(x)。対角は -（頂点の重みつき次数）、非対角は 2 w_ij",
    }
    path.write_text(dumps(data), encoding="utf-8")
    return path
