"""VQE で H2 の基底エネルギー（HEA、パラメータシフトの勾配法、深さ 1 と 2）。

ショットなし（状態ベクトルで厳密に期待値を出す）。同じ初期値の乱数の種で、仮説の深さだけを変える。
"""

from __future__ import annotations

import json
import time

import numpy as np
import plotting
from h2_sto3g import LIBRARY, reduced_hamiltonian
from vqe import error_mha, exact_energy, hea_state, parameter_count, parameter_shift_gradient

from sundesk_log import Run

SEED = 42
LEARNING_RATE = 0.4
ITERATIONS = 60
DEPTHS = (1, 2)
CHEMICAL_ACCURACY = 1.6e-3  # 1 kcal/mol ≒ 1.6 mHa


def main() -> None:
    hamiltonian, _, _ = reduced_hamiltonian()
    molecule = json.loads((LIBRARY / "Data/molecules/h2-sto3g-0.735.json").read_text())
    fci = molecule["energies"]["fci"]

    with Run(
        "VQE で H2（HEA、パラメータシフトの勾配法、深さ 1 と 2）",
        algorithm="VQE",
        problem="H2 STO-3G, 0.735 Å（パリティ写像、2 量子ビット）",
        parameters={
            "ansatz": "HEA (RY + CNOT)",
            "depths": "1, 2",
            "optimizer": "gradient descent (parameter shift)",
            "learning_rate": LEARNING_RATE,
            "iterations": ITERATIONS,
            "shots": 0,
            "init": "uniform(-π, π)",
        },
        seed=SEED,
        tags=["VQE", "H2", "勾配法"],
        objective="energy",
        direction="minimize",
        reference=fci,
        links=[
            "Papers/peruzzo2014-vqe",
            "Papers/kandala2017-hardware-efficient-vqe",
            "Data/molecules/h2-sto3g-0.735.json",
            "Data/code/vqe_h2_gd.py",
        ],
    ) as run:
        start = time.perf_counter()
        curves: dict[int, list[float]] = {}
        reached: dict[int, int] = {}
        evaluations: dict[int, int] = {}
        for depth in DEPTHS:
            rng = np.random.default_rng(SEED)
            params = rng.uniform(-np.pi, np.pi, parameter_count(depth))
            count = 0

            def energy(x: np.ndarray, depth: int = depth) -> float:
                nonlocal count
                count += 1
                return exact_energy(hea_state(x, depth), hamiltonian)

            values = []
            for iteration in range(ITERATIONS + 1):
                value = energy(params)
                values.append(value)
                if depth not in reached and value - fci < CHEMICAL_ACCURACY:
                    reached[depth] = iteration
                if iteration < ITERATIONS:
                    params = params - LEARNING_RATE * parameter_shift_gradient(energy, params)
            curves[depth] = values
            evaluations[depth] = count

        for iteration in range(ITERATIONS + 1):
            run.log(iteration=iteration, **{f"depth{d}": curves[d][iteration] for d in DEPTHS})
        elapsed = time.perf_counter() - start

        for depth in DEPTHS:
            run.metrics(
                **{
                    f"final_energy_depth{depth}": curves[depth][-1],
                    f"error_mha_depth{depth}": error_mha(curves[depth][-1], fci),
                    f"iterations_to_chemical_accuracy_depth{depth}": reached.get(depth, -1),
                    f"evaluations_depth{depth}": evaluations[depth],
                }
            )
        run.metrics(time_seconds=round(elapsed, 3))

        fig, ax = plotting.figure("H2 の VQE（勾配法）", "反復", "エネルギー (Ha)")
        x = list(range(ITERATIONS + 1))
        plotting.lines(ax, x, {f"深さ {d}": curves[d] for d in DEPTHS})
        plotting.reference_line(ax, fci, f"FCI {fci:.6f}")
        ax.set_ylim(fci - 0.05, max(max(c) for c in curves.values()) + 0.05)
        run.figure(fig, "convergence.png")


if __name__ == "__main__":
    main()
