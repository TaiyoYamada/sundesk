"""VQE で H2（HEA 深さ 1、ショット 1024、SPSA と CMA-ES を同じ評価回数で比べる）。

1 回の評価は、測定の基底 2 つ（ZZ と YY）× 1024 ショット。評価の回数をそろえて、
統計ゆらぎのもとでどちらが基底エネルギーに近づくかを見る。
記録するエネルギーは、その時点のパラメータ（CMA-ES は分布の平均）での厳密な期待値。
"""

from __future__ import annotations

import time

import numpy as np
import plotting
from h2_sto3g import reduced_hamiltonian
from vqe import CMAES, SPSA, ShotEstimator, exact_energy, hea_state, parameter_count

from sundesk_log import Run

SEEDS = [0, 1, 2, 3, 4]
DEPTH = 1
SHOTS = 1024
BUDGET = 1200  # 種ごとの評価の回数
SIGMA0 = 0.5
CHEMICAL_ACCURACY = 1.6e-3


def run_spsa(seed: int, hamiltonian, terms, repulsion) -> tuple[list[float], int]:
    rng = np.random.default_rng(seed)
    params = rng.uniform(-np.pi, np.pi, parameter_count(DEPTH))
    estimator = ShotEstimator(terms, repulsion, SHOTS, rng)
    optimizer = SPSA(a=0.6, c=0.1)

    def noisy(x: np.ndarray) -> float:
        return estimator(hea_state(x, DEPTH))

    curve = [exact_energy(hea_state(params, DEPTH), hamiltonian)]
    for k in range(BUDGET // 2):
        params = optimizer.step(noisy, params, k, rng)
        if (k + 1) % 4 == 0:  # 8 評価ごとに記録する
            curve.append(exact_energy(hea_state(params, DEPTH), hamiltonian))
    return curve, estimator.measurements


def run_cmaes(seed: int, hamiltonian, terms, repulsion) -> tuple[list[float], int]:
    rng = np.random.default_rng(seed)
    params = rng.uniform(-np.pi, np.pi, parameter_count(DEPTH))
    estimator = ShotEstimator(terms, repulsion, SHOTS, rng)
    strategy = CMAES(params, SIGMA0, rng)
    assert strategy.lam == 8
    curve = [exact_energy(hea_state(strategy.mean, DEPTH), hamiltonian)]
    for _ in range(BUDGET // strategy.lam):
        candidates = strategy.ask()
        fitness = np.array([estimator(hea_state(x, DEPTH)) for x in candidates])
        strategy.tell(candidates, fitness)
        curve.append(exact_energy(hea_state(strategy.mean, DEPTH), hamiltonian))
    return curve, estimator.measurements


def main() -> None:
    hamiltonian, terms, repulsion = reduced_hamiltonian()
    fci = float(np.linalg.eigvalsh(hamiltonian)[0])

    with Run(
        "VQE で H2（ショット 1024、SPSA と CMA-ES）",
        algorithm="VQE",
        problem="H2 STO-3G, 0.735 Å（パリティ写像、2 量子ビット）",
        parameters={
            "ansatz": "HEA (RY + CNOT)",
            "depth": DEPTH,
            "optimizers": "SPSA, CMA-ES",
            "shots": SHOTS,
            "measurement_bases": 2,
            "budget_evaluations": BUDGET,
            "spsa_a": 0.6,
            "spsa_c": 0.1,
            "cmaes_sigma0": SIGMA0,
            "cmaes_lambda": 8,
        },
        seed=SEEDS,
        tags=["VQE", "H2", "SPSA", "CMA-ES", "ショット雑音"],
        objective="energy",
        direction="minimize",
        reference=fci,
        links=[
            "Papers/peruzzo2014-vqe",
            "Papers/hansen2016-cma-es-tutorial",
            "Data/molecules/h2-sto3g-0.735.json",
            "Data/code/vqe_h2_shots.py",
        ],
    ) as run:
        start = time.perf_counter()
        spsa, cmaes = [], []
        measurements = 0
        for seed in SEEDS:
            curve, used = run_spsa(seed, hamiltonian, terms, repulsion)
            spsa.append(curve)
            measurements = used
            curve, _ = run_cmaes(seed, hamiltonian, terms, repulsion)
            cmaes.append(curve)
        elapsed = time.perf_counter() - start
        spsa_curves, cmaes_curves = np.array(spsa), np.array(cmaes)

        evaluations = [8 * g for g in range(spsa_curves.shape[1])]
        for g, count in enumerate(evaluations):
            run.log(
                evaluations=count,
                spsa=float(spsa_curves[:, g].mean()),
                cmaes=float(cmaes_curves[:, g].mean()),
            )
        spsa_errors = (spsa_curves[:, -1] - fci) * 1000
        cmaes_errors = (cmaes_curves[:, -1] - fci) * 1000
        run.metrics(
            spsa_mean_error_mha=float(spsa_errors.mean()),
            spsa_worst_error_mha=float(spsa_errors.max()),
            spsa_seeds_within_chemical_accuracy=int(np.sum(spsa_errors < 1.6)),
            cmaes_mean_error_mha=float(cmaes_errors.mean()),
            cmaes_worst_error_mha=float(cmaes_errors.max()),
            cmaes_seeds_within_chemical_accuracy=int(np.sum(cmaes_errors < 1.6)),
            measurements_per_seed=measurements,
            time_seconds=round(elapsed, 3),
        )

        fig, ax = plotting.figure(
            "H2 の VQE（ショット 1024、5 つの種の平均）", "評価の回数", "エネルギー (Ha)"
        )
        plotting.lines(
            ax,
            evaluations,
            {"SPSA": spsa_curves.mean(axis=0), "CMA-ES": cmaes_curves.mean(axis=0)},
            bands={
                "SPSA": (spsa_curves.min(axis=0), spsa_curves.max(axis=0)),
                "CMA-ES": (cmaes_curves.min(axis=0), cmaes_curves.max(axis=0)),
            },
        )
        plotting.reference_line(ax, fci, f"FCI {fci:.6f}")
        ax.set_ylim(fci - 0.05, max(float(spsa_curves.max()), float(cmaes_curves.max())) + 0.05)
        run.figure(fig, "convergence.png")

        # 最後の 1/3 を拡大した図も残す
        fig, ax = plotting.figure("終盤の拡大（FCI からの差）", "評価の回数", "FCI からの差 (mHa)")
        tail = len(evaluations) * 2 // 3
        plotting.lines(
            ax,
            evaluations[tail:],
            {
                "SPSA": (spsa_curves.mean(axis=0)[tail:] - fci) * 1000,
                "CMA-ES": (cmaes_curves.mean(axis=0)[tail:] - fci) * 1000,
            },
        )
        plotting.reference_line(ax, CHEMICAL_ACCURACY * 1000, "化学精度 1.6 mHa")
        run.figure(fig, "tail.png")


if __name__ == "__main__":
    main()
