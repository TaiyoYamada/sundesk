"""二値の粒子群最適化（Kennedy & Eberhart 1997 の離散版）で重みつき Max-Cut（maxcut-w30）を解く。

速度をシグモイドで確率に直し、各ビットを 1 にする確率とする。
"""

from __future__ import annotations

import time

import numpy as np
from benchmark import BUDGET, LINKS, SEEDS, record
from maxcut import load

from sundesk_log import Run

PARTICLES = 40
INERTIA = 0.7
COGNITIVE = 1.5
SOCIAL = 1.5
VMAX = 4.0


def solve(instance, rng: np.random.Generator) -> tuple[np.ndarray, int | None]:
    n = instance.n
    x = rng.integers(0, 2, size=(PARTICLES, n))
    v = rng.uniform(-1, 1, size=(PARTICLES, n))
    fitness = instance.cut(x)
    personal, personal_fitness = x.copy(), fitness.copy()
    leader = personal[np.argmax(personal_fitness)].copy()
    trace = list(np.maximum.accumulate(fitness))
    while len(trace) < BUDGET:
        r1, r2 = rng.random((PARTICLES, n)), rng.random((PARTICLES, n))
        v = INERTIA * v + COGNITIVE * r1 * (personal - x) + SOCIAL * r2 * (leader - x)
        v = np.clip(v, -VMAX, VMAX)
        x = (rng.random((PARTICLES, n)) < 1 / (1 + np.exp(-v))).astype(int)
        fitness = instance.cut(x)
        improved = fitness > personal_fitness
        personal[improved], personal_fitness[improved] = x[improved], fitness[improved]
        leader = personal[np.argmax(personal_fitness)].copy()
        best = trace[-1]
        for value in fitness[: BUDGET - len(trace)]:
            best = max(best, value)
            trace.append(best)
    curve = np.array(trace[:BUDGET])
    hit = np.flatnonzero(curve >= instance.optimum)
    return curve, (int(hit[0]) + 1 if hit.size else None)


def main() -> None:
    instance = load()
    with Run(
        "二値 PSO で重みつき Max-Cut（30 頂点）",
        algorithm="PSO",
        problem="重みつき Max-Cut, maxcut-w30（30 頂点、175 辺）",
        parameters={
            "variant": "binary PSO (sigmoid)",
            "particles": PARTICLES,
            "inertia": INERTIA,
            "c1": COGNITIVE,
            "c2": SOCIAL,
            "vmax": VMAX,
            "topology": "global best",
            "budget_evaluations": BUDGET,
        },
        seed=SEEDS,
        tags=["PSO", "Max-Cut", "群知能"],
        objective="cut",
        direction="maximize",
        reference=instance.optimum,
        links=["Papers/kennedy1995-pso", *LINKS, "Data/code/pso_maxcut.py"],
    ) as run:
        start = time.perf_counter()
        results = [solve(instance, np.random.default_rng(seed)) for seed in SEEDS]
        elapsed = time.perf_counter() - start
        record(
            run, instance, np.array([c for c, _ in results]), [h for _, h in results], "二値 PSO"
        )
        run.metrics(time_seconds=round(elapsed, 3))


if __name__ == "__main__":
    main()
