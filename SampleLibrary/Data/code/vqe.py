"""2 量子ビットの VQE の部品（状態ベクトルのシミュレーション、ショットの推定、最適化手法）。

量子ビット 0 を左（最上位のビット）に置く。numpy だけで書いている。
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np

CNOT = np.array(
    [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1], [0, 0, 1, 0]], dtype=float
)  # 制御 0、標的 1
HADAMARD = np.array([[1.0, 1.0], [1.0, -1.0]]) / np.sqrt(2)
S_DAGGER = np.diag([1.0, -1.0j])


def ry(theta: float) -> np.ndarray:
    c, s = np.cos(theta / 2), np.sin(theta / 2)
    return np.array([[c, -s], [s, c]])


def parameter_count(reps: int) -> int:
    return 2 * (reps + 1)


def hea_state(params: np.ndarray, reps: int) -> np.ndarray:
    """ハードウェア効率のよい仮説（RY の層と CNOT を交互に。Kandala 2017 の形を RY だけにしたもの）。

    |00> から始め、RY の層を reps + 1 回、その間に CNOT を reps 回はさむ。
    """
    state = np.zeros(4)
    state[0] = 1.0
    for layer in range(reps + 1):
        a, b = params[2 * layer], params[2 * layer + 1]
        state = np.kron(ry(a), ry(b)) @ state
        if layer < reps:
            state = CNOT @ state
    return state


def exact_energy(state: np.ndarray, hamiltonian: np.ndarray) -> float:
    return float(np.real(np.conj(state) @ hamiltonian @ state))


def error_mha(energy: float, reference: float) -> float:
    """参照値からの差（mHa）。変分法なので負にはならない。丸めの誤差で負になった分は 0 にする。"""
    return round(max((energy - reference) * 1000, 0.0), 6)


@dataclass
class ShotEstimator:
    """パウリ展開の各項を、測定の基底ごとにまとめて、有限のショットで推定する。

    1 回の推定で、基底の数 × shots 回の測定を使う。
    """

    terms: dict[str, float]
    constant: float
    shots: int
    rng: np.random.Generator
    groups: dict[str, list[str]] = field(init=False)
    measurements: int = field(default=0, init=False)

    def __post_init__(self) -> None:
        self.groups = {}
        for label in self.terms:
            if label == "II":
                continue
            basis = "".join("Z" if p == "I" else p for p in label)
            self.groups.setdefault(basis, []).append(label)

    @staticmethod
    def rotation(basis: str) -> np.ndarray:
        gates = {"Z": np.eye(2), "X": HADAMARD, "Y": HADAMARD @ S_DAGGER}
        return np.kron(gates[basis[0]], gates[basis[1]])

    def __call__(self, state: np.ndarray) -> float:
        energy = self.constant + self.terms.get("II", 0.0)
        for basis, labels in self.groups.items():
            amplitudes = self.rotation(basis) @ state
            probabilities = np.abs(amplitudes) ** 2
            probabilities /= probabilities.sum()
            counts = self.rng.multinomial(self.shots, probabilities)
            self.measurements += self.shots
            for label in labels:
                # 各ビットの固有値（0 → +1、1 → -1）の積。I の位置は数えない
                signs = np.ones(4)
                for index in range(4):
                    bits = ((index >> 1) & 1, index & 1)
                    for qubit, pauli in enumerate(label):
                        if pauli != "I" and bits[qubit]:
                            signs[index] *= -1
                energy += self.terms[label] * float(signs @ counts) / self.shots
        return energy


# MARK: - 最適化手法


def parameter_shift_gradient(f: Callable[[np.ndarray], float], params: np.ndarray) -> np.ndarray:
    """RY の角度についての厳密な勾配（パラメータシフト則）。2 × パラメータ数 回の評価を使う。"""
    gradient = np.zeros_like(params)
    for i in range(len(params)):
        shift = np.zeros_like(params)
        shift[i] = np.pi / 2
        gradient[i] = (f(params + shift) - f(params - shift)) / 2
    return gradient


@dataclass
class SPSA:
    """同時摂動確率近似（Spall 1992）。1 回の更新で 2 回だけ評価する。"""

    a: float = 0.2
    c: float = 0.1
    alpha: float = 0.602
    gamma: float = 0.101
    stability: float = 10.0

    def step(
        self, f: Callable[[np.ndarray], float], params: np.ndarray, k: int, rng: np.random.Generator
    ) -> np.ndarray:
        ak = self.a / (k + 1 + self.stability) ** self.alpha
        ck = self.c / (k + 1) ** self.gamma
        delta = rng.choice([-1.0, 1.0], size=len(params))
        difference = f(params + ck * delta) - f(params - ck * delta)
        return params - ak * difference / (2 * ck) * delta


class CMAES:
    """CMA-ES（Hansen 2016 のチュートリアルの標準の形。(μ/μ_w, λ)、CSA、rank-1 と rank-μ の更新）。"""

    def __init__(self, mean: np.ndarray, sigma: float, rng: np.random.Generator) -> None:
        n = len(mean)
        self.n = n
        self.mean = mean.astype(float).copy()
        self.sigma = sigma
        self.rng = rng
        self.lam = 4 + int(3 * np.log(n))
        self.mu = self.lam // 2
        weights = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.weights = weights / weights.sum()
        self.mueff = 1 / np.sum(self.weights**2)
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        self.c1 = 2 / ((n + 1.3) ** 2 + self.mueff)
        self.cmu = min(
            1 - self.c1, 2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff)
        )
        self.damps = 1 + 2 * max(0.0, np.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.chin = np.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n**2))
        self.pc = np.zeros(n)
        self.ps = np.zeros(n)
        self.cov = np.eye(n)
        self.generation = 0

    def ask(self) -> np.ndarray:
        values, vectors = np.linalg.eigh(self.cov)
        root = vectors @ np.diag(np.sqrt(np.maximum(values, 1e-20)))
        z = self.rng.standard_normal((self.lam, self.n))
        return self.mean + self.sigma * z @ root.T

    def tell(self, solutions: np.ndarray, fitness: np.ndarray) -> None:
        order = np.argsort(fitness)
        chosen = solutions[order[: self.mu]]
        old = self.mean
        self.mean = self.weights @ chosen
        values, vectors = np.linalg.eigh(self.cov)
        inverse_root = vectors @ np.diag(1 / np.sqrt(np.maximum(values, 1e-20))) @ vectors.T
        step = (self.mean - old) / self.sigma
        self.ps = (1 - self.cs) * self.ps + np.sqrt(
            self.cs * (2 - self.cs) * self.mueff
        ) * inverse_root @ step
        self.generation += 1
        threshold = (1.4 + 2 / (self.n + 1)) * self.chin
        norm = np.linalg.norm(self.ps) / np.sqrt(1 - (1 - self.cs) ** (2 * self.generation))
        hsig = float(norm < threshold)
        self.pc = (1 - self.cc) * self.pc + hsig * np.sqrt(
            self.cc * (2 - self.cc) * self.mueff
        ) * step
        artmp = (chosen - old) / self.sigma
        self.cov = (
            (1 - self.c1 - self.cmu) * self.cov
            + self.c1
            * (np.outer(self.pc, self.pc) + (1 - hsig) * self.cc * (2 - self.cc) * self.cov)
            + self.cmu * artmp.T @ np.diag(self.weights) @ artmp
        )
        self.sigma *= np.exp((self.cs / self.damps) * (np.linalg.norm(self.ps) / self.chin - 1))
