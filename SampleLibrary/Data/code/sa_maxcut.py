"""シミュレーテッドアニーリングで重みつき Max-Cut（maxcut-w30）を解く。GA と PSO と同じ評価の回数で比べる。

1 回のスピン反転の試行を 1 回の評価と数える（差分で計算するので、実際の計算はもっと軽い）。
温度は 30 から 0.3 まで等比で下げる。
"""

from __future__ import annotations

import time

import numpy as np
from anneal import geometric, simulated_annealing
from benchmark import BUDGET, LINKS, SEEDS, record
from maxcut import load

from sundesk_log import Run

T_START = 30.0
T_END = 0.3


def main() -> None:
    instance = load()
    n = instance.n
    sweeps = BUDGET // n
    with Run(
        "SA で重みつき Max-Cut（30 頂点、GA と PSO と同じ評価の回数）",
        algorithm="SA",
        problem="重みつき Max-Cut, maxcut-w30（30 頂点、175 辺）",
        parameters={
            "schedule": "geometric",
            "t_start": T_START,
            "t_end": T_END,
            "sweeps": sweeps,
            "move": "single spin flip (Metropolis)",
            "budget_evaluations": BUDGET,
        },
        seed=SEEDS,
        tags=["SA", "Max-Cut", "アニーリング"],
        objective="cut",
        direction="maximize",
        reference=instance.optimum,
        links=["Papers/kirkpatrick1983-simulated-annealing", *LINKS, "Data/code/sa_maxcut.py"],
    ) as run:
        start = time.perf_counter()
        curves = []
        for seed in SEEDS:
            best_per_sweep: list[float] = []

            def keep(_: int, best: np.ndarray, out: list[float] = best_per_sweep) -> None:
                out.append((instance.total_weight - float(best[0])) / 2)

            simulated_annealing(
                instance.weights,
                sweeps,
                geometric(T_START, T_END),
                1,
                np.random.default_rng(seed),
                on_sweep=keep,
            )
            # スイープの途中は、そのスイープの終わりの値で代表させる
            curves.append(np.repeat(best_per_sweep, n))
        elapsed = time.perf_counter() - start
        curves_array = np.array(curves)
        hits = []
        for curve in curves_array:
            hit = np.flatnonzero(curve >= instance.optimum)
            hits.append(int(hit[0]) + 1 if hit.size else None)
        record(run, instance, curves_array, hits, "SA")
        run.metrics(time_seconds=round(elapsed, 3))


if __name__ == "__main__":
    main()
