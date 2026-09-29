"""H2（STO-3G）のハミルトニアンを、積分から自分で作る。

- 1s の STO-3G（ζ = 1.24）の積分を解析式で計算する（Szabo & Ostlund の付録 A の式）
- 制限 Hartree-Fock で分子軌道を決め、スピン軌道 4 つを Jordan-Wigner で 4 量子ビットに写す
- 2 電子の空間で対角化して FCI のエネルギーを出す

VQE の実験では、この 4 量子ビットのものと、
パリティ写像で 2 量子ビットに縮めたもの（Data/molecules/h2-sto3g-0.735.json）を使う。
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

ANGSTROM = 1 / 0.52917721092  # 1 Å をボーアに直す係数
EXPONENTS = np.array([3.42525091, 0.62391373, 0.16885540])
COEFFICIENTS = np.array([0.15432897, 0.53532814, 0.44463454])

LIBRARY = Path(__file__).resolve().parents[2]


def boys0(t: float) -> float:
    if t < 1e-12:
        return 1.0
    return 0.5 * math.sqrt(math.pi / t) * math.erf(math.sqrt(t))


def primitives(center: float) -> list[tuple[float, float, float]]:
    """(指数, 正規化込みの係数, 中心の z 座標) の組。"""
    norms = (2 * EXPONENTS / math.pi) ** 0.75
    return [(a, d * n, center) for a, d, n in zip(EXPONENTS, COEFFICIENTS, norms, strict=True)]


def ao_integrals(r: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """核間距離 r（ボーア）の AO 積分: 重なり S、1 電子 h、2 電子 (ij|kl)。"""
    centers = [0.0, r]
    basis = [primitives(c) for c in centers]
    s = np.zeros((2, 2))
    h = np.zeros((2, 2))
    eri = np.zeros((2, 2, 2, 2))
    for i in range(2):
        for j in range(2):
            for a, ca, xa in basis[i]:
                for b, cb, xb in basis[j]:
                    p = a + b
                    xp = (a * xa + b * xb) / p
                    k = math.exp(-a * b / p * (xa - xb) ** 2)
                    overlap = (math.pi / p) ** 1.5 * k
                    s[i, j] += ca * cb * overlap
                    kinetic = a * b / p * (3 - 2 * a * b / p * (xa - xb) ** 2) * overlap
                    nuclear = sum(
                        -2 * math.pi / p * k * boys0(p * (xp - xc) ** 2) for xc in centers
                    )
                    h[i, j] += ca * cb * (kinetic + nuclear)
    for i, j, k_, l_ in np.ndindex(2, 2, 2, 2):
        total = 0.0
        for a, ca, xa in basis[i]:
            for b, cb, xb in basis[j]:
                for c, cc, xc in basis[k_]:
                    for d, cd, xd in basis[l_]:
                        p, q = a + b, c + d
                        xp, xq = (a * xa + b * xb) / p, (c * xc + d * xd) / q
                        value = (
                            2
                            * math.pi**2.5
                            / (p * q * math.sqrt(p + q))
                            * math.exp(-a * b / p * (xa - xb) ** 2 - c * d / q * (xc - xd) ** 2)
                            * boys0(p * q / (p + q) * (xp - xq) ** 2)
                        )
                        total += ca * cb * cc * cd * value
        eri[i, j, k_, l_] = total
    return s, h, eri


@dataclass
class Molecule:
    bond_length: float  # Å
    nuclear_repulsion: float
    hf_energy: float  # 核の反発を含む
    h_mo: np.ndarray
    eri_mo: np.ndarray


def hartree_fock(bond_length: float) -> Molecule:
    r = bond_length * ANGSTROM
    s, h, eri = ao_integrals(r)
    # 対称な直交化 S^(-1/2)
    values, vectors = np.linalg.eigh(s)
    x = vectors @ np.diag(values**-0.5) @ vectors.T
    density = np.zeros((2, 2))
    energy = 0.0
    c = np.eye(2)
    for _ in range(100):
        g = np.einsum("kl,ijkl->ij", density, eri) - 0.5 * np.einsum("kl,ikjl->ij", density, eri)
        fock = h + g
        e, cp = np.linalg.eigh(x.T @ fock @ x)
        c = x @ cp
        new_density = 2 * np.outer(c[:, 0], c[:, 0])
        new_energy = 0.5 * float(np.sum(new_density * (h + fock)))
        if abs(new_energy - energy) < 1e-12 and np.allclose(new_density, density, atol=1e-10):
            break
        density, energy = new_density, new_energy
        del e
    # 同じ密度でもう一度 Fock を作り、エネルギーを確定させる
    g = np.einsum("kl,ijkl->ij", density, eri) - 0.5 * np.einsum("kl,ikjl->ij", density, eri)
    energy = 0.5 * float(np.sum(density * (2 * h + g)))
    h_mo = c.T @ h @ c
    eri_mo = np.einsum("pi,qj,rk,sl,pqrs->ijkl", c, c, c, c, eri)
    repulsion = 1 / r
    return Molecule(bond_length, repulsion, energy + repulsion, h_mo, eri_mo)


# MARK: - Jordan-Wigner


def annihilation(p: int, n: int) -> np.ndarray:
    """a_p（量子ビット 0 が最上位のビット）。"""
    z = np.diag([1.0, -1.0])
    lower = np.array([[0.0, 1.0], [0.0, 0.0]])  # |1> → |0>
    ops = [z] * p + [lower] + [np.eye(2)] * (n - p - 1)
    out = ops[0]
    for op in ops[1:]:
        out = np.kron(out, op)
    return out


def qubit_hamiltonian(molecule: Molecule) -> np.ndarray:
    """スピン軌道 [0α, 0β, 1α, 1β] を量子ビット 0〜3 に置いた電子のハミルトニアン（核の反発を含む）。"""
    n = 4
    a = [annihilation(p, n) for p in range(n)]
    ad = [op.T for op in a]
    hamiltonian = molecule.nuclear_repulsion * np.eye(2**n)
    for p, q in np.ndindex(n, n):
        if p % 2 != q % 2:
            continue
        value = molecule.h_mo[p // 2, q // 2]
        hamiltonian += value * ad[p] @ a[q]
    for p, q, r, s in np.ndindex(n, n, n, n):
        # <pq|rs> = (pr|qs)、スピンがそろうものだけ残る
        if p % 2 != r % 2 or q % 2 != s % 2:
            continue
        value = molecule.eri_mo[p // 2, r // 2, q // 2, s // 2]
        if value != 0:
            hamiltonian += 0.5 * value * ad[p] @ ad[q] @ a[s] @ a[r]
    return hamiltonian


def number_operator(n: int = 4) -> np.ndarray:
    a = [annihilation(p, n) for p in range(n)]
    return sum((op.T @ op for op in a), np.zeros((2**n, 2**n)))


def fci_energy(hamiltonian: np.ndarray, electrons: int = 2) -> float:
    counts = np.round(np.diag(number_operator())).astype(int)
    index = np.flatnonzero(counts == electrons)
    return float(np.linalg.eigvalsh(hamiltonian[np.ix_(index, index)])[0])


def hartree_fock_state() -> np.ndarray:
    """|1100>（σg に 2 電子）。"""
    state = np.zeros(16)
    state[0b1100] = 1.0
    return state


# MARK: - 2 量子ビット（パリティ写像で縮めたもの）


PAULI = {
    "I": np.eye(2),
    "X": np.array([[0.0, 1.0], [1.0, 0.0]]),
    "Y": np.array([[0.0, -1.0j], [1.0j, 0.0]]),
    "Z": np.diag([1.0, -1.0]),
}


def parity_reduced(molecule: Molecule) -> tuple[np.ndarray, dict[str, float]]:
    """パリティ写像で 2 量子ビットに縮めたハミルトニアン（核の反発を含む）と、そのパウリ展開。

    スピン軌道を [0α, 1α, 0β, 1β] に並べ直してパリティ写像をかけると、量子ビット 1 は α 電子の数の偶奇、
    量子ビット 3 は全電子の数の偶奇になる。中性の H2（α と β が 1 つずつ）ではそれぞれ 1 と 0 に決まるので、
    残りの量子ビット 0 と 2 だけで書ける。
    """
    full = qubit_hamiltonian(molecule)
    chosen: list[tuple[int, int]] = []
    for index in range(16):
        a0, b0, a1, b1 = ((index >> (3 - q)) & 1 for q in range(4))
        parity = np.cumsum([a0, a1, b0, b1]) % 2
        if parity[1] == 1 and parity[3] == 0:
            chosen.append((int(parity[0]) * 2 + int(parity[2]), index))
    order = [index for _, index in sorted(chosen)]
    matrix = full[np.ix_(order, order)]
    terms: dict[str, float] = {}
    for first in "IXYZ":
        for second in "IXYZ":
            pauli = np.kron(PAULI[first], PAULI[second])
            value = float(np.trace(pauli @ matrix).real / 4)
            if abs(value) > 1e-12:
                terms[first + second] = value
    return matrix, terms


def reduced_hamiltonian(path: Path | None = None) -> tuple[np.ndarray, dict[str, float], float]:
    """Data/molecules/h2-sto3g-0.735.json の 2 量子ビットのハミルトニアン。

    (核の反発を含む行列, 電子の部分のパウリ展開, 核の反発) を返す。
    """
    path = path or LIBRARY / "Data/molecules/h2-sto3g-0.735.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    terms: dict[str, float] = data["pauli_terms"]
    repulsion: float = data["nuclear_repulsion"]
    matrix = repulsion * np.eye(4, dtype=complex)
    for label, value in terms.items():
        matrix = matrix + value * np.kron(PAULI[label[0]], PAULI[label[1]])
    return matrix.real, terms, repulsion


def write_molecule_file(bond_length: float = 0.735) -> Path:
    """0.735 Å のハミルトニアンを Data/molecules/ に書く。"""
    molecule = hartree_fock(bond_length)
    matrix, terms = parity_reduced(molecule)
    terms["II"] -= molecule.nuclear_repulsion
    data = {
        "molecule": "H2",
        "basis": "STO-3G",
        "bond_length_angstrom": bond_length,
        "mapping": "parity, 2-qubit reduction",
        "unit": "hartree",
        "nuclear_repulsion": molecule.nuclear_repulsion,
        "pauli_terms": terms,
        "energies": {
            "hartree_fock": molecule.hf_energy,
            "fci": float(np.linalg.eigvalsh(matrix)[0]),
        },
        "hartree_fock_state": "10",
        "note": (
            "Data/code/h2_sto3g.py で積分から作った。pauli_terms は電子の部分だけで、"
            "全エネルギーは nuclear_repulsion を足したもの。Qiskit のチュートリアルの係数とは、"
            "量子ビットの順（IZ と ZI）と、XX が YY になっている点だけが違う（固有値は同じ）"
        ),
    }
    path = LIBRARY / f"Data/molecules/h2-sto3g-{bond_length}.json"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


if __name__ == "__main__":
    for length in (0.735, 1.4 / ANGSTROM):
        m = hartree_fock(length)
        print(
            f"R = {length:.4f} Å: HF {m.hf_energy:.8f}  FCI {fci_energy(qubit_hamiltonian(m)):.8f}"
        )
    print(write_molecule_file())
