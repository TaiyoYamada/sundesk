"""イジング形の Max-Cut に対する SA と SQA（numpy だけ、複数の試行を同時に進める）。

どちらも E(s) = Σ_{i<j} w_ij s_i s_j を最小にする。カットは (W - E) / 2。
"""

from __future__ import annotations

from collections.abc import Callable

import numpy as np

Schedule = Callable[[float], float]  # 進み具合 t ∈ [0, 1] → 温度（または横磁場）


def geometric(start: float, end: float) -> Schedule:
    return lambda t: start * (end / start) ** t


def linear(start: float, end: float) -> Schedule:
    return lambda t: start + (end - start) * t


def linear_beta(start: float, end: float) -> Schedule:
    """逆温度 β = 1/T を線形に上げる。"""
    return lambda t: 1 / (1 / start + (1 / end - 1 / start) * t)


def simulated_annealing(
    weights: np.ndarray,
    sweeps: int,
    temperature: Schedule,
    replicas: int,
    rng: np.random.Generator,
    on_sweep: Callable[[int, np.ndarray], None] | None = None,
) -> np.ndarray:
    """メトロポリス法の SA。1 スイープで全スピンを順に 1 回ずつ試す。最後のスピンの配置を返す。

    `on_sweep(sweep, best_energy)` を渡すと、各スイープの後に、試行ごとのそれまでの最良のエネルギーを渡す。
    """
    n = len(weights)
    s = rng.choice([-1.0, 1.0], size=(replicas, n))
    field = s @ weights  # h_i = Σ_j w_ij s_j
    energy = np.einsum("ri,ri->r", s, field) / 2
    best = energy.copy()
    for sweep in range(sweeps):
        t = temperature(sweep / max(sweeps - 1, 1))
        for i in range(n):
            delta = -2 * s[:, i] * field[:, i]
            accept = (delta <= 0) | (rng.random(replicas) < np.exp(-np.maximum(delta, 0) / t))
            flip = np.where(accept, s[:, i], 0.0)
            field -= 2 * flip[:, None] * weights[i][None, :]
            s[:, i] -= 2 * flip
            energy += np.where(accept, delta, 0.0)
            np.minimum(best, energy, out=best)
        if on_sweep is not None:
            on_sweep(sweep, best)
    return s


def simulated_quantum_annealing(
    weights: np.ndarray,
    sweeps: int,
    gamma: Schedule,
    temperature: float,
    slices: int,
    replicas: int,
    rng: np.random.Generator,
) -> np.ndarray:
    """経路積分モンテカルロによる SQA（Martoňák, Santoro, Tosatti 2002 の形）。

    鈴木-トロッターで P 枚のスライスに分け、スライスの間を J⊥ = -(PT/2) ln tanh(Γ/(PT)) でつなぐ。
    古典の相互作用はスライスごとに 1/P 倍する。同じスピンのスライスは偶数番と奇数番に分けて同時に更新する。
    戻り値は (replicas, slices) の、各スライスの最後の古典エネルギー。
    """
    n = len(weights)
    p = slices
    s = rng.choice([-1.0, 1.0], size=(replicas, p, n))
    field = s @ weights  # (replicas, P, n)
    parity = [np.arange(0, p, 2), np.arange(1, p, 2)]
    pt = p * temperature
    for sweep in range(sweeps):
        g = gamma(sweep / max(sweeps - 1, 1))
        j_perp = -0.5 * pt * np.log(np.tanh(g / pt))
        for i in range(n):
            for ks in parity:
                up = s[:, (ks + 1) % p, i]
                down = s[:, (ks - 1) % p, i]
                spin = s[:, ks, i]
                # 有効エネルギー（温度 T で割る前）の変化: 古典の分は 1/P、トロッター方向は -J⊥ s s'
                delta = -2 * spin * field[:, ks, i] / p + 2 * j_perp * spin * (up + down)
                accept = (delta <= 0) | (
                    rng.random(delta.shape) < np.exp(-np.maximum(delta, 0) / temperature)
                )
                flip = np.where(accept, spin, 0.0)
                field[:, ks, :] -= 2 * flip[:, :, None] * weights[i][None, None, :]
                s[:, ks, i] -= 2 * flip
    return np.einsum("rki,rki->rk", s, field) / 2
