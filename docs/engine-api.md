# エンジンの API

アプリ（Swift）と AI エンジン（Python）の間の約束。エンジンは状態を持たず、計算した結果を返すだけにする。
保存はアプリが行う（[ADR 0003](adr/0003-swiftdata-single-source-of-truth.md)）。

## 共通

- `127.0.0.1` の HTTP。すべての要求に `Authorization: Bearer <起動ごとのトークン>` を付ける（[ADR 0006](adr/0006-engine-http-over-loopback.md)）
- 本文は JSON。キーは snake_case
- 失敗したときは 4xx / 5xx と `{"detail": "日本語のメッセージ"}` を返す
  - 400: 要求の中身がおかしい
  - 404: モデルやファイルが見つからない
  - 422: 対応していないモデルの構造など
  - 500: それ以外
- 時間のかかる処理は **NDJSON**（`application/x-ndjson`。1 行に 1 つの JSON）で逐次返す。各行は `type` を持つ
  - 途中で失敗したら `{"type": "error", "message": "..."}` を流して終える
- 文字の位置は Python の `str` の添字（Unicode のコードポイント）で数える
- モデルは Hugging Face の ID（`mlx-community/Qwen3-0.6B-4bit` など）で指す。ダウンロードは Hugging Face の標準のキャッシュ（`~/.cache/huggingface/hub`）に置く

### メモリの使い方

- 大きいモデル（LLM か画像生成）は、同時に 1 つだけ載せる。別のモデルを求められたら、前のものを捨ててから載せる
- 埋め込みモデルは小さいので、別枠で載せたままにする
- LoRA のアダプタは、LLM を載せるときに合わせて読む（アダプタが変われば載せ直す）

## フェーズ 0: 死活確認

`GET /health` → `{"status": "ok", "version": "0.1.0", "python_version": "3.13.13"}`

## フェーズ 2: 知識グラフ

### `POST /graph/build`

ノートを受け取り、概念（点）、出現（概念とチャンクの対応）、関係（線）を作って返す。

```json
{
  "notes": [
    {
      "path": "数学/固有値.md",
      "title": "固有値",
      "links": ["数学/線形代数.md"],
      "chunks": [
        {"id": "数学/固有値.md#0", "heading_path": ["固有値", "定義"], "text": "固有値とは、…"}
      ]
    }
  ],
  "options": {"max_concepts": 1500, "min_frequency": 2, "similarity": false}
}
```

- `text` は、コードと数式を除いた本文（アプリが用意する）
- `links` は、解決済みのリンク先のパス
- `similarity` が true なら、概念の名前を埋め込み、意味の近い概念を `similar` の線で結ぶ（フェーズ 3 以降）

```json
{
  "concepts": [
    {"id": 0, "label": "固有値", "normalized": "固有値", "score": 12.3, "frequency": 10,
     "pagerank": 0.012, "community": 3}
  ],
  "mentions": [{"concept": 0, "chunk": "数学/固有値.md#0", "count": 3}],
  "relations": [
    {"source": 0, "target": 5, "kind": "cooccurrence", "weight": 2.1, "evidence": "数学/固有値.md#0"}
  ]
}
```

| 項目 | 内容 |
|---|---|
| 概念の抽出 | SudachiPy で形態素解析し、名詞の連続（と英字の語）を候補にする。C-value と出現数で重要度（`score`）を付け、上位を採る。ノートのタイトルは必ず概念にする |
| 正規化 | NFKC と、英字の小文字化。機械的に同じと言えるものだけをまとめる |
| `cooccurrence` | 同じチャンクに出る語の組。PMI が正のものだけ。重みは PMI × 共起数の対数 |
| `hierarchy` | 見出しの概念 → その節の本文に出る重要な概念 |
| `definition` | 「A とは B である」「A は B のことである」 |
| `is_a` | 「A は B の一種」「A は B の一つ」 |
| `link` | ノートのリンク（タイトルの概念どうし） |
| `contains` | 複合語が別の概念を含む（「固有値分解」→「固有値」） |
| `similar` | 埋め込みの類似度が高い（`similarity` が true のときだけ） |
| 分析 | networkx の PageRank（重み付き）と、Louvain 法のコミュニティ検出（乱数の種は固定） |

## フェーズ 3: RAG

### `POST /embeddings`

```json
{"texts": ["固有値とは"], "kind": "query", "model": "cl-nagoya/ruri-v3-130m"}
```

- `kind` は `query`（質問）か `document`（チャンク）。ruri-v3 の決まりどおり、前に「検索クエリ: 」「検索文書: 」を付けて埋め込む
- `model` は省略できる（既定は `cl-nagoya/ruri-v3-130m`）

→ `{"model": "cl-nagoya/ruri-v3-130m", "dimension": 512, "vectors": [[0.01, …]]}`（長さ 1 に正規化済み）

### `POST /chat`（NDJSON）

```json
{
  "model": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
  "messages": [{"role": "system", "content": "…"}, {"role": "user", "content": "…"}],
  "max_tokens": 1024, "temperature": 0.7, "top_p": 0.95, "adapter": null
}
```

```
{"type": "loading", "model": "…"}          ← モデルを載せ始めたとき（載っていれば出ない）
{"type": "token", "text": "固有"}
{"type": "done", "prompt_tokens": 812, "generated_tokens": 230, "tokens_per_second": 31.2}
```

出典の番号づけとプロンプトの組み立ては、アプリが行う。

## フェーズ 4: モデルの管理と LLM 実験室

### モデル

| 要求 | 応答 |
|---|---|
| `GET /models` | `{"models": [{"id", "kind": "llm" \| "embedding" \| "image" \| "other", "size_bytes", "path"}]}` 手元にあるモデル |
| `POST /models/download`（NDJSON） `{"id"}` | `{"type": "progress", "downloaded_bytes", "total_bytes"}` … `{"type": "done", "path"}` |
| `DELETE /models/{id}` | `{"deleted": true}` |
| `GET /models/loaded` | `{"llm": id \| null, "image": id \| null, "embedding": id \| null, "adapter": path \| null}` |
| `POST /models/unload` `{"kind": "llm" \| "image" \| "all"}` | `{"unloaded": [...]}` |

### 覗く

どれも `model` と `prompt` を取る。`chat_template` が true なら、`prompt` をユーザーの発言としてチャットの形に包んでから使う。
対応するのは、mlx-lm のモデルのうち `model.model.embed_tokens`、`layers`、`norm` を持つもの（Llama、Qwen、Mistral など）。
それ以外は 422 を返す。重い計算を避けるため、プロンプトは 512 トークンまでにする（超えたら 400）。

| 要求 | 応答 |
|---|---|
| `POST /lab/tokenize` `{"model", "text"}` | `{"tokens": [{"id", "text", "start", "end"}]}` 区切り。位置が決まらない断片は `start`、`end` が null |
| `POST /lab/next-token` `{"model", "prompt", "chat_template", "top_k": 20, "temperature": 1.0}` | `{"tokens": [{"id", "text", "probability", "logit"}], "entropy"}` 次のトークンの確率（上位 `top_k`） |
| `POST /lab/generate`（NDJSON） `{"model", "prompt", "chat_template", "max_tokens", "temperature", "top_p", "top_k", "seed", "alternatives": 5, "adapter"}` | `{"type": "token", "id", "text", "probability", "alternatives": [{"id", "text", "probability"}]}` … `{"type": "done", "generated_tokens", "tokens_per_second"}` 1 トークンずつ、選ばれたものと他の候補 |
| `POST /lab/attention` `{"model", "prompt", "chat_template", "layer"}` | `{"tokens": [{"id", "text"}], "num_layers", "num_heads", "layer", "heads": [[[f]]], "mean": [[f]]}` 指定した層の Attention（ヘッドごと、`heads[h][i][j]` は i 番目のトークンが j 番目を見る重み）と、ヘッドの平均 |
| `POST /lab/logit-lens` `{"model", "prompt", "chat_template", "top_k": 3}` | `{"tokens", "num_layers", "layers": [{"layer", "positions": [{"top": [{"id", "text", "probability"}]}]}]}` 各層の途中の状態を最後の正規化と出力層に通したときの予測 |
| `POST /lab/activations` `{"model", "prompt", "chat_template"}` | `{"tokens", "num_layers", "norms": [[f]]}` 各層・各位置の残差ストリームの大きさ（L2 ノルム。`norms[layer][position]`） |

## フェーズ 5: 画像生成

| 要求 | 応答 |
|---|---|
| `GET /images/models` | `{"models": [{"id": "z-image-turbo", "name", "repo", "downloaded", "default_steps", "default_size"}]}` 使える画像モデル |
| `POST /images/generate`（NDJSON） | 下を参照 |

```json
{"model": "z-image-turbo", "prompt": "…", "width": 1024, "height": 1024, "steps": null, "seed": null,
 "quantize": 4, "output_path": "/Users/…/Images/2026-09-29-123456.png"}
```

```
{"type": "loading", "model": "z-image-turbo"}
{"type": "progress", "step": 3, "total": 9}
{"type": "done", "path": "/Users/…/2026-09-29-123456.png", "seed": 42, "seconds": 38.2}
```

- 生成は mflux で行う。候補は FLUX.2 klein 4B と Z-Image Turbo
- `seed` が null なら、エンジンが決めて `done` で返す。保存先はアプリが決める

## フェーズ 6: いじる

### `POST /lora/train`（NDJSON）

```json
{"model": "mlx-community/Qwen3-0.6B-4bit", "texts": ["ノートの本文…"], "adapter_path": "/Users/…/Adapters/名前",
 "iterations": 200, "rank": 8, "learning_rate": 1e-5, "batch_size": 1, "max_seq_length": 1024, "num_layers": 8}
```

```
{"type": "loading", "model": "…"}
{"type": "progress", "iteration": 10, "total": 200, "train_loss": 2.31}
{"type": "validation", "iteration": 50, "val_loss": 2.10}
{"type": "done", "adapter_path": "/Users/…/Adapters/名前"}
```

- `texts` をそのまま続きを書く学習（completion）に使う。1 割を検証に回す
- できたアダプタは、`/chat` と `/lab/generate` の `adapter` に渡して使う

### steering

| 要求 | 応答 |
|---|---|
| `POST /steering/vector` `{"model", "layer", "positive": [str], "negative": [str]}` | `{"layer", "vector": [f], "norm"}` 指定した層の残差ストリームの平均の差（positive − negative。最後のトークンの位置） |
| `POST /steering/generate` `{"model", "prompt", "chat_template", "layer", "vector", "strength", "max_tokens", "temperature", "seed"}` | `{"baseline": str, "steered": str}` 同じ種で、ベクトルを足さない生成と足した生成 |
