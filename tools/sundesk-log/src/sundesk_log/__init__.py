"""実験の結果を sundesk の取り込み箱へ書く記録用ライブラリ。

実行ごとに取り込み箱（`Inbox/<実行の ID>/`）へ `run.json`、`results/`、`figures/` を書き、
終わったら空のファイル `.complete` を置く。アプリはそれを見つけて `Experiments/` へ移す。
形は docs/library-format.md に従う。

    from sundesk_log import Run

    with Run("VQE で H2", algorithm="VQE", problem="H2 STO-3G", objective="energy") as run:
        for i in range(100):
            run.log(iteration=i, energy=...)
        run.metrics(best_energy=...)
"""

from sundesk_log._run import FIGURE_SUFFIXES, INBOX_ENV, Run, SavesFigure, Trace, default_inbox

__all__ = ["FIGURE_SUFFIXES", "INBOX_ENV", "Run", "SavesFigure", "Trace", "default_inbox"]
__version__ = "0.1.0"
