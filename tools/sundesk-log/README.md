# sundesk-log

実験のスクリプトから、結果を sundesk の取り込み箱へ書くための小さな Python ライブラリ。
依存するライブラリはない（Python 3.10 以上）。

実行ごとに `Inbox/<実行の ID>/` を作って `run.json`、`results/`、`figures/` を書き、
終わったら空のファイル `.complete` を置く。アプリはそれを見つけて `Experiments/` へ移す。
形は [docs/library-format.md](../../docs/library-format.md) のとおり。

## 入れかた

```sh
uv add --editable path/to/tools/sundesk-log
# または
pip install -e path/to/tools/sundesk-log
```

## 使いかた

```python
from sundesk_log import Run

with Run(
    "VQE で H2 の基底エネルギー",
    algorithm="VQE",
    problem="H2 STO-3G, 0.735 Å",
    parameters={"ansatz": "HEA", "optimizer": "SPSA", "shots": 1024},
    seed=42,
    tags=["VQE", "H2"],
    objective="energy",
    direction="minimize",
    reference=-1.137306,
) as run:
    for i in range(100):
        ...
        run.log(iteration=i, energy=energy, best=best)  # results/trace.csv に 1 行足す
    run.metrics(best_energy=best, time_seconds=elapsed)
    run.figure(fig, "convergence.png")  # matplotlib の図を figures/ に保存する
    run.attach("params.json")  # 図は figures/、ほかは results/ に写す
    run.link("Papers/peruzzo2014-vqe", "Data/h2-sto3g-0.735.json")
    run.note("## 仮説\n\n...")  # note.md の本文
```

- `with` を抜けると `status` が `done` になる。例外で抜けたときは `failed` にして、例外はそのまま投げ直す
- `run.log()` の最初の列が横軸になり、残りの列が縦軸になる。行はすぐにファイルへ書く。
  途中で新しい列が出てきたら、見出しを増やして CSV を書き直す
- 曲線を分けたいときは `run.trace("scan", x="bond_length").log(...)` で `results/scan.csv` に書く
- `metrics` は数だけ、`parameters` は文字、数、真偽だけ（入れ子にしない）を受け付ける。NaN や無限大は JSON に書けないので断る
- 取り込み箱の場所は、引数 `inbox=`、環境変数 `SUNDESK_INBOX`、
  `~/Library/Application Support/com.taiyou.sundesk/Library/Inbox` の順に決まる

## 開発

```sh
make lint-log   # ruff と pyright
make test-log   # pytest
```
