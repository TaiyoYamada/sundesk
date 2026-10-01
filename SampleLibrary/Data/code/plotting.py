"""実験の図の見た目をそろえる。"""

from __future__ import annotations

from collections.abc import Sequence

import matplotlib as mpl

mpl.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.axes import Axes
from matplotlib.figure import Figure

# 系列の色はこの順に使う（青、橙、青緑）。3 本までにする
COLORS = ["#2a78d6", "#eb6834", "#1baf7a"]
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
MUTED = "#52514e"
GRID = "#e4e3df"

plt.rcParams.update(
    {
        "font.family": ["Hiragino Sans"],
        "font.size": 9,
        "axes.facecolor": SURFACE,
        "figure.facecolor": SURFACE,
        "axes.edgecolor": GRID,
        "axes.labelcolor": MUTED,
        "axes.titlecolor": INK,
        "axes.titlesize": 10,
        "axes.titlelocation": "left",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.color": GRID,
        "grid.linewidth": 0.6,
        "xtick.color": MUTED,
        "ytick.color": MUTED,
        "legend.frameon": False,
        "lines.linewidth": 1.6,
        "savefig.dpi": 110,
    }
)


def figure(title: str, xlabel: str, ylabel: str) -> tuple[Figure, Axes]:
    fig, ax = plt.subplots(figsize=(6.0, 3.4), layout="constrained")
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    return fig, ax


def reference_line(ax: Axes, value: float, label: str) -> None:
    ax.axhline(value, color=MUTED, linewidth=1.0, linestyle=(0, (4, 3)))
    ax.annotate(
        label,
        xy=(1.0, value),
        xycoords=("axes fraction", "data"),
        xytext=(-4, 4),
        textcoords="offset points",
        ha="right",
        va="bottom",
        color=MUTED,
        fontsize=8,
    )


def lines(
    ax: Axes,
    x: Sequence[float],
    series: dict[str, Sequence[float]],
    *,
    bands: dict[str, tuple[Sequence[float], Sequence[float]]] | None = None,
) -> None:
    """系列を描く。`bands` があれば、その範囲を薄く塗る（種ごとのばらつきなど）。"""
    for color, (label, values) in zip(COLORS, series.items(), strict=False):
        if bands and label in bands:
            low, high = bands[label]
            ax.fill_between(x, low, high, color=color, alpha=0.15, linewidth=0)
        ax.plot(x, values, color=color, label=label)
    if len(series) >= 2:
        ax.legend(loc="best")
