"""SA の始めの温度を変える（maxcut-w30、等比のスケジュール、300 スイープ）。

sa_schedules.py では、スイープを増やしても成功確率が 0.7 ほどで頭打ちになった。
始めの温度が高すぎて、前半のスイープを無駄にしているのではないかを確かめる。
"""

from __future__ import annotations

import time

import numpy as np
import plotting
from anneal import geometric, simulated_annealing
from maxcut import load

from sundesk_log import Run

SEED = 23
REPLICAS = 200
SWEEPS = 300
T_END = 0.3
T_STARTS = [1.0, 3.0, 10.0, 30.0, 100.0]


def main() -> None:
    instance = load()
    optimum_energy = instance.total_weight - 2 * instance.optimum
    with Run(
        "SA の始めの温度を変える（Max-Cut 30 頂点、300 スイープ）",
        algorithm="SA",
        problem="重みつき Max-Cut, maxcut-w30（30 頂点、175 辺）",
        parameters={
            "schedule": "geometric",
            "t_starts": ", ".join(f"{t:g}" for t in T_STARTS),
            "t_end": T_END,
            "sweeps": SWEEPS,
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
            "Data/code/sa_start_temperature.py",
        ],
    ) as run:
        run.note(
            "## 仮説\n\n"
            "等比のスケジュールでは、温度が高い前半はほぼランダムウォークになる。"
            "始めの温度を 30 から 3〜10 に下げれば、同じ 300 スイープでも成功確率が上がるはず。"
            "1 まで下げると、始めから凍って局所解に捕まりやすくなると予想する。"
        )
        start = time.perf_counter()
        rng = np.random.default_rng(SEED)
        results = []
        for t_start in T_STARTS:
            spins = simulated_annealing(
                instance.weights, SWEEPS, geometric(t_start, T_END), REPLICAS, rng
            )
            energies = instance.ising_energy(spins)
            success = float(np.mean(energies <= optimum_energy + 1e-9))
            mean_cut = float(np.mean((instance.total_weight - energies) / 2))
            results.append(success)
            run.log(t_start=t_start, success=success, mean_cut_ratio=mean_cut / instance.optimum)
        elapsed = time.perf_counter() - start
        best = int(np.argmax(results))
        run.metrics(
            best_t_start=T_STARTS[best],
            best_success=results[best],
            success_at_t30=results[T_STARTS.index(30.0)],
            time_seconds=round(elapsed, 3),
        )

        fig, ax = plotting.figure(
            "始めの温度と成功確率（300 スイープ、200 回ずつ）", "始めの温度", "割合"
        )
        plotting.lines(ax, T_STARTS, {"最適解に届いた割合": results})
        ax.plot(
            T_STARTS, results, linestyle="none", marker="o", markersize=4, color=plotting.COLORS[0]
        )
        ax.set_xscale("log")
        ax.minorticks_off()
        ax.set_xticks(T_STARTS, [f"{v:g}" for v in T_STARTS])
        ax.set_ylim(0, 1.05)
        run.figure(fig, "success.png")


if __name__ == "__main__":
    main()
