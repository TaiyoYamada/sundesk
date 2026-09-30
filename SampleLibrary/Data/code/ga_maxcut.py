"""遺伝的アルゴリズムで重みつき Max-Cut（maxcut-w30）を解く。

トーナメント選択、一様交叉、ビット反転の突然変異、エリート保存。
"""

from __future__ import annotations

import time

import numpy as np
from benchmark import BUDGET, LINKS, SEEDS, record
from maxcut import load

from sundesk_log import Run

POPULATION = 50
TOURNAMENT = 3
CROSSOVER = 0.9
ELITES = 2


def solve(instance, rng: np.random.Generator) -> tuple[np.ndarray, int | None]:
    n = instance.n
    mutation = 1 / n
    population = rng.integers(0, 2, size=(POPULATION, n))
    fitness = instance.cut(population)
    trace = list(np.maximum.accumulate(fitness))
    while len(trace) < BUDGET:
        order = np.argsort(-fitness)
        elites = population[order[:ELITES]]
        count = POPULATION - ELITES
        contestants = rng.integers(0, POPULATION, size=(2 * count, TOURNAMENT))
        winners = contestants[np.arange(2 * count), np.argmax(fitness[contestants], axis=1)]
        mothers, fathers = population[winners[:count]], population[winners[count:]]
        mask = rng.random((count, n)) < 0.5
        cross = rng.random(count) < CROSSOVER
        children = np.where(mask & cross[:, None], fathers, mothers)
        children ^= (rng.random((count, n)) < mutation).astype(children.dtype)
        child_fitness = instance.cut(children)
        best = trace[-1]
        for value in child_fitness[: BUDGET - len(trace)]:
            best = max(best, value)
            trace.append(best)
        population = np.vstack([elites, children])
        fitness = np.concatenate([fitness[order[:ELITES]], child_fitness])
    curve = np.array(trace[:BUDGET])
    hit = np.flatnonzero(curve >= instance.optimum)
    return curve, (int(hit[0]) + 1 if hit.size else None)


def main() -> None:
    instance = load()
    with Run(
        "GA で重みつき Max-Cut（30 頂点）",
        algorithm="GA",
        problem="重みつき Max-Cut, maxcut-w30（30 頂点、175 辺）",
        parameters={
            "population": POPULATION,
            "selection": "tournament",
            "tournament_size": TOURNAMENT,
            "crossover": "uniform",
            "crossover_rate": CROSSOVER,
            "mutation_rate": "1/n",
            "elites": ELITES,
            "budget_evaluations": BUDGET,
        },
        seed=SEEDS,
        tags=["GA", "Max-Cut", "進化計算"],
        objective="cut",
        direction="maximize",
        reference=instance.optimum,
        links=[*LINKS, "Data/code/ga_maxcut.py"],
    ) as run:
        start = time.perf_counter()
        results = [solve(instance, np.random.default_rng(seed)) for seed in SEEDS]
        elapsed = time.perf_counter() - start
        record(run, instance, np.array([c for c, _ in results]), [h for _, h in results], "GA")
        run.metrics(time_seconds=round(elapsed, 3))


if __name__ == "__main__":
    main()
