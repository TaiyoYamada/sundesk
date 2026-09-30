"""GA、PSO、SA を同じ評価の回数で比べるための共通の部分。"""

from __future__ import annotations

import numpy as np
import plotting
from maxcut import MaxCut

from sundesk_log import Run

SEEDS = list(range(10))
BUDGET = 20_000  # 種ごとの評価の回数
LOG_EVERY = 200
LINKS = [
    "Papers/lucas2014-ising-formulations",
    "Data/instances/maxcut-w30.json",
]


def record(
    run: Run, instance: MaxCut, curves: np.ndarray, hits: list[int | None], label: str
) -> None:
    """curves は (種, 評価の回数) のそれまでの最良のカット。hits は最適値に初めて届いた評価の回数。"""
    axis = list(range(0, curves.shape[1], LOG_EVERY))
    if axis[-1] != curves.shape[1] - 1:
        axis.append(curves.shape[1] - 1)
    for k in axis:
        column = curves[:, k]
        run.log(
            evaluations=k + 1,
            mean=float(column.mean()),
            best=float(column.max()),
            worst=float(column.min()),
        )
    final = curves[:, -1]
    reached = [h for h in hits if h is not None]
    run.metrics(
        best_cut=float(final.max()),
        mean_cut=float(final.mean()),
        worst_cut=float(final.min()),
        mean_gap_percent=round(
            float((instance.optimum - final.mean()) / instance.optimum * 100), 4
        ),
        success_rate=len(reached) / len(hits),
        evaluations_per_seed=int(curves.shape[1]),
    )
    if reached:
        run.metrics(median_evaluations_to_optimum=float(np.median(reached)))

    fig, ax = plotting.figure(
        f"{label} の収束（maxcut-w30、{len(hits)} つの種）", "評価の回数", "それまでの最良のカット"
    )
    x = np.array(axis) + 1
    plotting.lines(
        ax,
        x,
        {"種の平均": curves[:, axis].mean(axis=0)},
        bands={"種の平均": (curves[:, axis].min(axis=0), curves[:, axis].max(axis=0))},
    )
    plotting.reference_line(ax, instance.optimum, f"最適値 {instance.optimum:.0f}")
    ax.set_ylim(instance.optimum - 80, instance.optimum + 10)
    run.figure(fig, "convergence.png")
