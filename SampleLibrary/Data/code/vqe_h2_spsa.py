"""VQE で H2 の基底エネルギー（HEA 深さ 1、SPSA、ショットなし、5 つの種）。

SPSA は 1 回の更新で 2 回しか評価しないが、方向がばらつく。種ごとの差を見る。
"""

from __future__ import annotations

import json
import time

import numpy as np
import plotting
from h2_sto3g import LIBRARY, reduced_hamiltonian
from vqe import SPSA, exact_energy, hea_state, parameter_count

from sundesk_log import Run

SEEDS = [0, 1, 2, 3, 4]
DEPTH = 1
ITERATIONS = 300
GAIN_A = 0.6
GAIN_C = 0.1
CHEMICAL_ACCURACY = 1.6e-3


def main() -> None:
    hamiltonian, _, _ = reduced_hamiltonian()
    molecule = json.loads((LIBRARY / "Data/molecules/h2-sto3g-0.735.json").read_text())
    fci = molecule["energies"]["fci"]
    optimizer = SPSA(a=GAIN_A, c=GAIN_C)

    with Run(
        "VQE で H2（HEA 深さ 1、SPSA、ショットなし）",
        algorithm="VQE",
        problem="H2 STO-3G, 0.735 Å（パリティ写像、2 量子ビット）",
        parameters={
            "ansatz": "HEA (RY + CNOT)",
            "depth": DEPTH,
            "optimizer": "SPSA",
            "a": GAIN_A,
            "c": GAIN_C,
            "alpha": optimizer.alpha,
            "gamma": optimizer.gamma,
            "A": optimizer.stability,
            "iterations": ITERATIONS,
            "shots": 0,
        },
        seed=SEEDS,
        tags=["VQE", "H2", "SPSA"],
        objective="energy",
        direction="minimize",
        reference=fci,
        links=[
            "Papers/peruzzo2014-vqe",
            "Papers/kandala2017-hardware-efficient-vqe",
            "Data/molecules/h2-sto3g-0.735.json",
            "Data/code/vqe_h2_spsa.py",
        ],
    ) as run:
        start = time.perf_counter()

        def energy(x: np.ndarray) -> float:
            return exact_energy(hea_state(x, DEPTH), hamiltonian)

        curves = np.zeros((len(SEEDS), ITERATIONS + 1))
        for row, seed in enumerate(SEEDS):
            rng = np.random.default_rng(seed)
            params = rng.uniform(-np.pi, np.pi, parameter_count(DEPTH))
            for k in range(ITERATIONS + 1):
                curves[row, k] = energy(params)
                if k < ITERATIONS:
                    params = optimizer.step(energy, params, k, rng)
        elapsed = time.perf_counter() - start

        for k in range(ITERATIONS + 1):
            column = curves[:, k]
            run.log(
                iteration=k,
                mean=float(column.mean()),
                best=float(column.min()),
                worst=float(column.max()),
            )
        errors = (curves[:, -1] - fci) * 1000
        run.metrics(
            best_energy=float(curves[:, -1].min()),
            mean_error_mha=float(errors.mean()),
            median_error_mha=float(np.median(errors)),
            worst_error_mha=float(errors.max()),
            seeds_within_chemical_accuracy=int(np.sum(errors < CHEMICAL_ACCURACY * 1000)),
            evaluations_per_seed=2 * ITERATIONS,
            time_seconds=round(elapsed, 3),
        )

        fig, ax = plotting.figure("H2 の VQE（SPSA、5 つの種）", "反復", "エネルギー (Ha)")
        x = list(range(ITERATIONS + 1))
        plotting.lines(
            ax,
            x,
            {"種の平均": curves.mean(axis=0)},
            bands={"種の平均": (curves.min(axis=0), curves.max(axis=0))},
        )
        plotting.reference_line(ax, fci, f"FCI {fci:.6f}")
        ax.set_ylim(fci - 0.05, float(curves.max()) + 0.05)
        run.figure(fig, "convergence.png")


if __name__ == "__main__":
    main()
