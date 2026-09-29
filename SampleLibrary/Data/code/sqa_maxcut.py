"""シミュレーテッド量子アニーリング（経路積分モンテカルロ）で Max-Cut（maxcut-w30）を解き、SA と比べる。

横磁場 Γ を 10 から 0.01 まで線形に下げる。温度 T = 0.25、トロッターのスライス P = 16。
SA は、1 回あたりのスピン更新の回数をそろえるため、SQA の P 倍のスイープを使う（等比、30 → 0.3）。
"""

from __future__ import annotations

import time

import numpy as np
import plotting
from anneal import geometric, linear, simulated_annealing, simulated_quantum_annealing
from maxcut import load

from sundesk_log import Run

SEED = 5
REPLICAS = 100
SLICES = 16
TEMPERATURE = 0.25
GAMMA_START, GAMMA_END = 10.0, 0.01
SWEEPS = [10, 30, 100, 300, 1000]


def main() -> None:
    instance = load()
    optimum_energy = instance.total_weight - 2 * instance.optimum
    with Run(
        "SQA と SA の比較（Max-Cut 30 頂点、スピン更新の回数をそろえる）",
        algorithm="QA",
        problem="重みつき Max-Cut, maxcut-w30（30 頂点、175 辺）",
        parameters={
            "method": "simulated quantum annealing (path-integral Monte Carlo)",
            "slices": SLICES,
            "temperature": TEMPERATURE,
            "gamma_start": GAMMA_START,
            "gamma_end": GAMMA_END,
            "gamma_schedule": "linear",
            "sweeps": ", ".join(map(str, SWEEPS)),
            "replicas": REPLICAS,
            "sa_schedule": "geometric 30 → 0.3, sweeps × 16",
        },
        seed=SEED,
        tags=["QA", "SQA", "SA", "Max-Cut", "アニーリング"],
        objective="success_probability",
        direction="maximize",
        reference=1.0,
        links=[
            "Papers/kadowaki1998-quantum-annealing",
            "Papers/kirkpatrick1983-simulated-annealing",
            "Data/instances/maxcut-w30.json",
            "Data/code/anneal.py",
            "Data/code/sqa_maxcut.py",
        ],
    ) as run:
        start = time.perf_counter()
        rng = np.random.default_rng(SEED)
        rows = []
        for sweeps in SWEEPS:
            energies = simulated_quantum_annealing(
                instance.weights,
                sweeps,
                linear(GAMMA_START, GAMMA_END),
                TEMPERATURE,
                SLICES,
                REPLICAS,
                rng,
            )
            hit = energies <= optimum_energy + 1e-9
            spins = simulated_annealing(
                instance.weights, sweeps * SLICES, geometric(30.0, 0.3), REPLICAS, rng
            )
            sa = float(np.mean(instance.ising_energy(spins) <= optimum_energy + 1e-9))
            row = {
                "sqa_slice": float(hit.mean()),
                "sqa_best_slice": float(hit.any(axis=1).mean()),
                "sa_equal_updates": sa,
            }
            rows.append(row)
            run.log(sweeps=sweeps, **row)
        elapsed = time.perf_counter() - start

        last = rows[-1]
        run.metrics(
            sqa_slice_success_at_1000=last["sqa_slice"],
            sqa_best_slice_success_at_1000=last["sqa_best_slice"],
            sa_success_at_16000=last["sa_equal_updates"],
            time_seconds=round(elapsed, 3),
        )

        fig, ax = plotting.figure(
            "SQA と SA（スピン更新の回数をそろえる、100 回ずつ）",
            "SQA のスイープの数（SA はその 16 倍）",
            "最適解に届いた割合",
        )
        series = {
            "SQA（スライス 1 枚）": [r["sqa_slice"] for r in rows],
            "SQA（16 枚の最良）": [r["sqa_best_slice"] for r in rows],
            "SA": [r["sa_equal_updates"] for r in rows],
        }
        plotting.lines(ax, SWEEPS, series)
        for color, values in zip(plotting.COLORS, series.values(), strict=False):
            ax.plot(SWEEPS, values, linestyle="none", marker="o", markersize=4, color=color)
        ax.set_xscale("log")
        ax.minorticks_off()
        ax.set_xticks(SWEEPS, [str(v) for v in SWEEPS])
        ax.set_ylim(0, 1.05)
        run.figure(fig, "success.png")


if __name__ == "__main__":
    main()
