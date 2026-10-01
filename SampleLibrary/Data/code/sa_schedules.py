"""SA の温度スケジュールを比べる（maxcut-w30）。

温度を等比で下げる、線形で下げる、逆温度を線形に上げるの 3 つを、スイープの数を変えて試す。
どれも温度は 30 から 0.3 まで。各条件 200 回ずつ走らせ、最後の配置が最適解である割合（成功確率）を数える。
"""

from __future__ import annotations

import math
import time

import numpy as np
import plotting
from anneal import geometric, linear, linear_beta, simulated_annealing
from maxcut import load

from sundesk_log import Run

SEED = 11
REPLICAS = 200
SWEEPS = [10, 30, 100, 300, 1000, 3000]
T_START, T_END = 30.0, 0.3
SCHEDULES = {
    "geometric": geometric(T_START, T_END),
    "linear": linear(T_START, T_END),
    "linear_beta": linear_beta(T_START, T_END),
}
LABELS = {"geometric": "等比", "linear": "線形", "linear_beta": "逆温度が線形"}


def tts99(sweeps: int, probability: float) -> float | None:
    """99% の確率で 1 度は最適解を得るまでのスイープの数（time to solution）。"""
    if probability <= 0:
        return None
    if probability >= 1:
        return float(sweeps)
    return sweeps * math.log(0.01) / math.log(1 - probability)


def main() -> None:
    instance = load()
    optimum_energy = instance.total_weight - 2 * instance.optimum
    with Run(
        "SA の温度スケジュールの比較（Max-Cut 30 頂点）",
        algorithm="SA",
        problem="重みつき Max-Cut, maxcut-w30（30 頂点、175 辺）",
        parameters={
            "schedules": "geometric, linear, linear_beta",
            "t_start": T_START,
            "t_end": T_END,
            "sweeps": ", ".join(map(str, SWEEPS)),
            "replicas": REPLICAS,
            "success": "final state is optimal",
        },
        seed=SEED,
        tags=["SA", "Max-Cut", "アニーリング", "スケジュール"],
        objective="success_probability",
        direction="maximize",
        reference=1.0,
        links=[
            "Papers/kirkpatrick1983-simulated-annealing",
            "Data/instances/maxcut-w30.json",
            "Data/code/anneal.py",
            "Data/code/sa_schedules.py",
        ],
    ) as run:
        start = time.perf_counter()
        rng = np.random.default_rng(SEED)
        table: dict[str, list[float]] = {name: [] for name in SCHEDULES}
        for sweeps in SWEEPS:
            row: dict[str, float] = {}
            for name, schedule in SCHEDULES.items():
                spins = simulated_annealing(instance.weights, sweeps, schedule, REPLICAS, rng)
                success = float(np.mean(instance.ising_energy(spins) <= optimum_energy + 1e-9))
                row[name] = success
                table[name].append(success)
            run.log(sweeps=sweeps, **row)
        elapsed = time.perf_counter() - start

        for name, probabilities in table.items():
            candidates = [tts99(s, p) for s, p in zip(SWEEPS, probabilities, strict=True)]
            finite = [c for c in candidates if c is not None]
            run.metrics(**{f"success_at_3000_{name}": probabilities[-1]})
            if finite:
                run.metrics(**{f"best_tts99_sweeps_{name}": round(min(finite), 1)})
        run.metrics(time_seconds=round(elapsed, 3))

        fig, ax = plotting.figure(
            "SA のスケジュールと成功確率（200 回ずつ）", "スイープの数", "最適解に届いた割合"
        )
        plotting.lines(ax, SWEEPS, {LABELS[k]: v for k, v in table.items()})
        for color, values in zip(plotting.COLORS, table.values(), strict=False):
            ax.plot(SWEEPS, values, linestyle="none", marker="o", markersize=4, color=color)
        ax.set_xscale("log")
        ax.minorticks_off()
        ax.set_xticks(SWEEPS, [str(v) for v in SWEEPS])
        ax.set_ylim(0, 1.05)
        run.figure(fig, "success.png")


if __name__ == "__main__":
    main()
