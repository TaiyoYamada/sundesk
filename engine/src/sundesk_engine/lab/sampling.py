"""次のトークンの確率と、そこからの抽選。

実験室では「選ばれたトークンの確率」と「他の候補」を見せたいので、mlx-lm の sampler ではなく、
確率を明示的に計算してから numpy で抽選する。
"""

from dataclasses import dataclass

import mlx.core as mx
import numpy as np
from numpy.typing import NDArray

from sundesk_engine.lab.arrays import to_float

type Probabilities = NDArray[np.float64]


@dataclass(frozen=True)
class SamplingOptions:
    temperature: float
    top_p: float = 1.0
    top_k: int = 0

    @property
    def greedy(self) -> bool:
        return self.temperature <= 0


def probabilities(logits: mx.array, temperature: float) -> Probabilities:
    """温度を掛けた確率。

    温度が 0 以下のとき（常に最も高いものを選ぶとき）は、温度 1 の確率を返す。
    すべてを 0 と 1 にしてしまうと、他の候補の様子が見えなくなるため。
    """
    values = to_float(logits)
    scaled = values / (temperature if temperature > 0 else 1.0)
    scaled -= scaled.max()
    exponentials = np.exp(scaled)
    return exponentials / exponentials.sum()


def entropy(probs: Probabilities) -> float:
    """エントロピー（単位は nat）。"""
    positive = probs[probs > 0]
    return float(-(positive * np.log(positive)).sum())


def top_indices(probs: Probabilities, count: int, exclude: int | None = None) -> list[int]:
    """確率の高い順に `count` 個の ID を返す。"""
    if count <= 0:
        return []
    size = min(count + (1 if exclude is not None else 0), probs.shape[0])
    candidates = np.argpartition(-probs, size - 1)[:size]
    ordered = sorted(candidates.tolist(), key=lambda index: (-probs[index], index))
    return [int(index) for index in ordered if index != exclude][:count]


def sample(probs: Probabilities, options: SamplingOptions, rng: np.random.Generator) -> int:
    """top-k と top-p で候補を絞ってから抽選する。"""
    if options.greedy:
        return int(np.argmax(probs))
    filtered = probs.copy()
    if options.top_k > 0 and options.top_k < filtered.shape[0]:
        threshold = np.partition(filtered, -options.top_k)[-options.top_k]
        filtered[filtered < threshold] = 0.0
    if 0 < options.top_p < 1:
        order = np.argsort(-filtered, kind="stable")
        cumulative: Probabilities = np.cumsum(filtered[order])
        limit = options.top_p * float(cumulative[-1])
        cutoff = int(np.searchsorted(cumulative, limit)) + 1
        keep = np.zeros_like(filtered, dtype=bool)
        keep[order[:cutoff]] = True
        filtered[~keep] = 0.0
    total = filtered.sum()
    if total <= 0:
        return int(np.argmax(probs))
    weights: Probabilities = filtered / total
    return int(rng.choice(int(filtered.shape[0]), p=weights))
