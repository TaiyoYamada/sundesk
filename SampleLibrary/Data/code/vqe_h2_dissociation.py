"""H2 の解離曲線（STO-3G）: Hartree-Fock、VQE（HEA 深さ 1）、FCI を比べる。

核間距離ごとに h2_sto3g.py で積分からハミルトニアンを作り、パリティ写像で 2 量子ビットに縮める。
VQE はショットなし、パラメータシフトの勾配法で、乱数の初期値から 3 回始めて最もよいものを採る。
"""

from __future__ import annotations

import time

import numpy as np
import plotting
from h2_sto3g import hartree_fock, parity_reduced
from vqe import error_mha, exact_energy, hea_state, parameter_count, parameter_shift_gradient

from sundesk_log import Run

SEED = 7
DEPTH = 1
RESTARTS = 3
ITERATIONS = 150
LEARNING_RATE = 0.4
BOND_LENGTHS = [round(0.3 + 0.05 * i, 2) for i in range(55)]  # 0.3〜3.0 Å


def vqe(hamiltonian: np.ndarray, rng: np.random.Generator) -> tuple[float, int]:
    count = 0

    def energy(x: np.ndarray) -> float:
        nonlocal count
        count += 1
        return exact_energy(hea_state(x, DEPTH), hamiltonian)

    best = np.inf
    for _ in range(RESTARTS):
        params = rng.uniform(-np.pi, np.pi, parameter_count(DEPTH))
        for _ in range(ITERATIONS):
            params = params - LEARNING_RATE * parameter_shift_gradient(energy, params)
        best = min(best, energy(params))
    return float(best), count


def main() -> None:
    with Run(
        "H2 の解離曲線（HF、VQE、FCI）",
        algorithm="VQE",
        problem="H2 STO-3G, 0.3〜3.0 Å（パリティ写像、2 量子ビット）",
        parameters={
            "ansatz": "HEA (RY + CNOT)",
            "depth": DEPTH,
            "optimizer": "gradient descent (parameter shift)",
            "learning_rate": LEARNING_RATE,
            "iterations": ITERATIONS,
            "restarts": RESTARTS,
            "points": len(BOND_LENGTHS),
            "shots": 0,
        },
        seed=SEED,
        tags=["VQE", "H2", "解離曲線", "静的相関"],
        objective="energy",
        direction="minimize",
        links=[
            "Papers/peruzzo2014-vqe",
            "Papers/kandala2017-hardware-efficient-vqe",
            "Data/code/h2_sto3g.py",
            "Data/code/vqe_h2_dissociation.py",
        ],
    ) as run:
        start = time.perf_counter()
        rng = np.random.default_rng(SEED)
        curve = run.trace("curve", x="bond_length")
        errors = run.trace("error", x="bond_length")
        rows = []
        evaluations = 0
        for length in BOND_LENGTHS:
            molecule = hartree_fock(length)
            hamiltonian, _ = parity_reduced(molecule)
            fci = float(np.linalg.eigvalsh(hamiltonian)[0])
            energy, count = vqe(hamiltonian, rng)
            evaluations += count
            curve.log(bond_length=length, hf=molecule.hf_energy, vqe=energy, fci=fci)
            errors.log(
                bond_length=length,
                vqe_error_mha=error_mha(energy, fci),
                hf_error_mha=error_mha(molecule.hf_energy, fci),
            )
            rows.append((length, molecule.hf_energy, energy, fci))
        elapsed = time.perf_counter() - start

        table = np.array(rows)
        lengths, hf, vqe_energy, fci = table.T
        minimum = int(np.argmin(fci))
        run.metrics(
            equilibrium_bond_length=float(lengths[minimum]),
            min_fci_energy=float(fci[minimum]),
            min_vqe_energy=float(vqe_energy.min()),
            max_vqe_error_mha=max(error_mha(e, f) for e, f in zip(vqe_energy, fci, strict=True)),
            hf_error_at_3_0_mha=error_mha(hf[-1], fci[-1]),
            hf_error_at_equilibrium_mha=error_mha(hf[minimum], fci[minimum]),
            evaluations=evaluations,
            time_seconds=round(elapsed, 3),
        )

        fig, ax = plotting.figure("H2 の解離曲線（STO-3G）", "核間距離 (Å)", "エネルギー (Ha)")
        ax.plot(lengths, hf, color=plotting.COLORS[1], label="Hartree-Fock")
        ax.plot(
            lengths, fci, color=plotting.MUTED, linewidth=1.0, linestyle=(0, (4, 3)), label="FCI"
        )
        ax.plot(
            lengths,
            vqe_energy,
            color=plotting.COLORS[0],
            linestyle="none",
            marker="o",
            markersize=4,
            label="VQE",
        )
        ax.legend(loc="upper right")
        run.figure(fig, "dissociation.png")


if __name__ == "__main__":
    main()
