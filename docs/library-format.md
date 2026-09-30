# 研究ライブラリの形式

sundesk の研究ライブラリは、アプリのデータフォルダの中のふつうのファイルでできている。
ファイルが正で、SwiftData の索引はそこから作り直せる（[requirements.md](requirements.md) の C 案）。

- 置き場所: `~/Library/Application Support/com.taiyou.sundesk/Library/`
- `~/Research` と study-artifact は、コピーせずに一番上の `Research/`、`study-artifact/` としてつなぐ（読むだけ。[ADR 0016](adr/0016-read-research-in-place.md)）
- テストでは、リポジトリの `SampleLibrary/`（研究向けの見本）を使う

```
Library/
├── Notes/            ノート（研究ログ、アイデア、議事メモ、下書き）。Markdown。フォルダで分けてよい
├── Papers/           論文。1 本につき 1 フォルダ
│   └── <キー>/
│       ├── note.md   書誌情報（フロントマター）と論文メモ
│       └── paper.pdf 本文（なくてもよい）
├── Experiments/      実験。1 回につき 1 フォルダ
│   └── <キー>/
│       ├── experiment.json   設定と結果の要約
│       ├── note.md           仮説と考察
│       ├── results/          結果のファイル（CSV、JSON）
│       └── figures/          図
├── Data/             コードとデータ（QUBO の行列、ベンチマークのインスタンス、分子、実験のコード）
├── Materials/        資料（発表のスライド、画像、そのほかの文書）
└── Inbox/            取り込み箱。記録用ライブラリがここに書き、アプリが見張って Experiments/ へ移す
```

`<キー>` は英数字、`-`、`_`、`.` だけでできた名前（例: `peruzzo2014-vqe`、`2026-09-20-vqe-h2-uccsd`）。

## 論文（`Papers/<キー>/note.md`）

```markdown
---
type: paper
title: "A variational eigenvalue solver on a photonic quantum processor"
authors: [Alberto Peruzzo, Jarrod McClean, Peter Shadbolt]
year: 2014
venue: Nature Communications
arxiv: "1304.3061"
doi: "10.1038/ncomms5213"
url: "https://arxiv.org/abs/1304.3061"
status: 読了
tags: [VQE, 量子化学]
added: 2026-09-29
---
# A variational eigenvalue solver on a photonic quantum processor

## 要点

## メモ
```

| 項目 | 内容 |
|---|---|
| `type` | 必ず `paper` |
| `title`、`authors`、`year` | 題名、著者（配列）、年 |
| `venue` | 雑誌や会議（なくてもよい） |
| `arxiv`、`doi`、`url` | なくてもよい。文字列で書く |
| `status` | `未読`、`読書中`、`読了` のどれか |
| `tags` | 配列 |
| `added` | 追加した日（`YYYY-MM-DD`） |
| `pdf` | 写さずに指している PDF（`Research/paper/example.pdf` のようなライブラリの中でのパス）。`paper.pdf` があればそちらを使う |

## 実験（`Experiments/<キー>/experiment.json`）

```json
{
  "title": "VQE で H2 の基底エネルギー（UCCSD、COBYLA）",
  "algorithm": "VQE",
  "problem": "H2 STO-3G, 0.735 Å",
  "status": "done",
  "created": "2026-09-20T10:00:00+09:00",
  "finished": "2026-09-20T10:03:12+09:00",
  "tags": ["VQE", "H2"],
  "parameters": {"ansatz": "UCCSD", "optimizer": "COBYLA", "shots": 0, "max_iterations": 200},
  "seed": 42,
  "objective": {"name": "energy", "direction": "minimize", "reference": -1.137270174},
  "metrics": {"best_energy": -1.1372, "time_seconds": 12.3, "evaluations": 180},
  "series": [{"file": "results/trace.csv", "x": "iteration", "y": ["energy", "best"]}],
  "attachments": ["figures/convergence.png"],
  "links": ["Papers/peruzzo2014-vqe", "Data/h2-sto3g.json"]
}
```

| 項目 | 内容 |
|---|---|
| `title` | 実験の名前 |
| `algorithm` | `VQE`、`QAOA`、`GA`、`PSO`、`SA`、`QA`（量子アニーリング）、`CMA-ES` など |
| `problem` | 解いた問題とインスタンス |
| `status` | `planned`、`running`、`done`、`failed` |
| `created`、`finished` | ISO 8601 の日時（`finished` はなくてもよい） |
| `parameters` | 名前と値（文字、数、真偽）の組。入れ子にしない |
| `seed` | 乱数の種（なくてもよい）。複数なら `seeds` に配列で |
| `objective` | 目的関数の名前、`minimize` か `maximize`、分かっていれば最適値（`reference`） |
| `metrics` | 結果の要約（名前と数） |
| `series` | 収束などの曲線。`file` は `results/` の CSV、`x` はその列名、`y` は描く列名の配列 |
| `attachments` | 図やそのほかのファイル（実験のフォルダからの相対パス） |
| `links` | 関係する論文やデータ（ライブラリのルートからの相対パス） |

`results/*.csv` は 1 行目が列名で、2 行目からが数。`note.md` は `type: experiment` と `title` のフロントマターを持ち、
本文に仮説（`## 仮説`）と考察（`## 考察`）を書く。

## 取り込み箱（`Inbox/<実行の ID>/`）

記録用ライブラリ（`tools/sundesk-log`）は、実行ごとにフォルダを作り、`experiment.json` と同じ形の `run.json`、
`results/`、`figures/` を書く。

- 実行中は `run.json` の `status` を `running` にしておく
- 終わったら `status` を `done`（失敗なら `failed`）にし、最後に空のファイル `.complete` を置く
- アプリは `.complete` のあるフォルダを見つけると、`Experiments/<キー>/` へ移し、`run.json` を `experiment.json` にし、
  `note.md` がなければ作る。キーは `YYYY-MM-DD-<題名から作った名前>`（重なれば `-2`、`-3` …）
- 取り込み箱の場所は、環境変数 `SUNDESK_INBOX` で変えられる（テスト用）
