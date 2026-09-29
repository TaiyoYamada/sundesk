# エンジンの API

アプリ（Swift）と AI エンジン（Python）の間の約束。エンジンは状態を持たず、計算した結果を返すだけにする。
保存はアプリが行う（[ADR 0003](adr/0003-swiftdata-single-source-of-truth.md)）。

## 共通

- `127.0.0.1` の HTTP。すべての要求に `Authorization: Bearer <起動ごとのトークン>` を付ける（[ADR 0006](adr/0006-engine-http-over-loopback.md)）
- 本文は JSON。キーは snake_case
- 失敗したときは 4xx / 5xx と `{"detail": "日本語のメッセージ"}` を返す
  - 400: 要求の中身がおかしい（型や範囲の検査に通らないものも 400 にする）
  - 404: モデルやファイルが見つからない。**モデルは勝手にダウンロードしない**。手元になければ 404 を返すので、
    アプリが先に `/models/download` で取り込む
  - 422: 対応していないモデルの構造など
  - 500: それ以外
- 時間のかかる処理は **NDJSON**（`application/x-ndjson`。1 行に 1 つの JSON）で逐次返す。各行は `type` を持つ
  - 途中で失敗したら `{"type": "error", "message": "..."}` を流して終える
- 文字の位置は Python の `str` の添字（Unicode のコードポイント）で数える
- モデルは Hugging Face の ID（`mlx-community/Qwen3-0.6B-4bit` など）か、手元のフォルダの絶対パスで指す。
  ダウンロードは Hugging Face の標準のキャッシュ（`~/.cache/huggingface/hub`）に置く
- LoRA のアダプタ（`adapter`）は絶対パスで指す。`adapter_config.json` と `adapters.safetensors` がなければ 404
- MLX の重い計算は 1 本のスレッドで順に行う（同時に 2 つのモデルを動かさない）

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
- `similarity` が true なら、概念の名前を埋め込み、意味の近い概念を `similar` の線で結ぶ（類似度 0.9 以上）
- `options` には、ほかに `min_cooccurrence`（既定 2）、`similarity_threshold`（既定 0.9）、`embedding_model` も渡せる
- 概念は `score` の大きい順に 0 から番号を振る。`score` は C-value × log2(1 + 出てくるチャンクの数)
- `evidence` は、関係を見つけたチャンクの ID（`link`、`contains`、`similar` では始点の概念が最初に出るチャンク）

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
| `cooccurrence` | 同じチャンクに出る語の組。PMI が正で、2 回以上共起したものだけ。重みは PMI × ln(1 + 共起数)。1 つの概念につき上位 20 本まで |
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
  "max_tokens": 1024, "temperature": 0.7, "top_p": 0.95, "adapter": null, "thinking": true
}
```

- `thinking` を `false` にすると、考える過程（Qwen3 の `<think>`）を飛ばすようチャットの型に伝える（`enable_thinking=False`）。知らない型は無視する

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

どれも `model` と `prompt` を取り、`adapter` も渡せる。`layer` は 0 始まり（負なら後ろから数える）。`chat_template` が true なら、`prompt` をユーザーの発言としてチャットの形に包んでから使う。
対応するのは、mlx-lm のモデルのうち `model.model.embed_tokens`、`layers`、`norm` を持つもの（Llama、Qwen、Mistral など）。
それ以外は 422 を返す。重い計算を避けるため、プロンプトは 512 トークンまでにする（超えたら 400）。

| 要求 | 応答 |
|---|---|
| `POST /lab/tokenize` `{"model", "text"}` | `{"tokens": [{"id", "text", "start", "end"}]}` 区切り（特別なトークンは付けない）。位置が決まらない断片は `start`、`end` が null |
| `POST /lab/next-token` `{"model", "prompt", "chat_template", "top_k": 20, "temperature": 1.0}` | `{"tokens": [{"id", "text", "probability", "logit"}], "entropy"}` 次のトークンの確率（上位 `top_k`）。エントロピーは自然対数（nat） |
| `POST /lab/generate`（NDJSON） `{"model", "prompt", "chat_template", "max_tokens", "temperature", "top_p", "top_k", "seed", "alternatives": 5, "adapter"}` | `{"type": "token", "id", "text", "probability", "alternatives": [{"id", "text", "probability"}]}` … `{"type": "done", "generated_tokens", "tokens_per_second"}` 1 トークンずつ、選ばれたものと他の候補。`text` は新しく確定した文字（UTF-8 の途中なら空）で、つなげると出力そのものになる。512 トークンを超えると `error` の行で終える |
| `POST /lab/attention` `{"model", "prompt", "chat_template", "layer"}` | `{"tokens": [{"id", "text"}], "num_layers", "num_heads", "layer", "heads": [[[f]]], "mean": [[f]]}` 指定した層の Attention（ヘッドごと、`heads[h][i][j]` は i 番目のトークンが j 番目を見る重み）と、ヘッドの平均 |
| `POST /lab/logit-lens` `{"model", "prompt", "chat_template", "top_k": 3}` | `{"tokens", "num_layers", "layers": [{"layer", "positions": [{"top": [{"id", "text", "probability"}]}]}]}` 各層の途中の状態を最後の正規化と出力層に通したときの予測 |
| `POST /lab/activations` `{"model", "prompt", "chat_template"}` | `{"tokens", "num_layers", "norms": [[f]]}` 各層・各位置の残差ストリームの大きさ（L2 ノルム。`norms[layer][position]`） |

## フェーズ 5: 画像生成

| 要求 | 応答 |
|---|---|
| `GET /images/models` | `{"models": [{"id": "z-image-turbo", "name", "repo", "downloaded", "default_steps", "default_size": {"width", "height"}}]}` 使える画像モデル（`z-image-turbo`、`flux2-klein-4b`）。取り込むときは `repo` を `/models/download` に渡す |
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
- `seed` が null なら、エンジンが決めて `done` で返す。保存先はアプリが決める（絶対パス）
- `width`、`height` は 256〜2048 の 16 の倍数。`quantize` は 3、4、5、6、8 か null

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
- `num_layers` が -1 ならすべての層。進み具合は 10 回ごとに流す。学習が終わると、モデルはメモリから外す
- できたアダプタは、`/chat` と `/lab/generate` の `adapter` に渡して使う

### steering

| 要求 | 応答 |
|---|---|
| `POST /steering/vector` `{"model", "layer", "positive": [str], "negative": [str]}` | `{"layer", "vector": [f], "norm"}` 指定した層の残差ストリームの平均の差（positive − negative。最後のトークンの位置） |
| `POST /steering/generate` `{"model", "prompt", "chat_template", "layer", "vector", "strength", "max_tokens", "temperature", "seed"}` | `{"baseline": str, "steered": str}` 同じ種で、ベクトルを足さない生成と足した生成（`seed` が null なら毎回変える） |

## フェーズ 7: 工房（作る・比べる・書く）

モデルを量子化し、変換し、混ぜ、枝を刈り、蒸留して、できたものを比べる。Python を書いて、載せたモデルを直接いじることもできる。

### 作ったモデルの置き場所

- 作ったモデル（量子化、変換、焼き込み、合成、枝刈り、蒸留）は、アプリが決めた `output_dir`（絶対パス）に MLX の形式で書く
  （`config.json`、重み、トークナイザ。`mlx_lm.load(output_dir)` でそのまま読めること）
- アプリはエンジンの起動時に、環境変数 `SUNDESK_MODELS_DIR` でそのフォルダの親を渡す。`GET /models` は、Hugging Face のキャッシュに加えて、
  ここにあるフォルダも返す（`id` は絶対パス）
- `GET /models` の各項目に `name`（表示名。キャッシュならリポジトリ名、手元ならフォルダ名）と `source`（`"hub"` か `"local"`）を足す

作る処理はどれも NDJSON で、次の形の行を流す。

```
{"type": "loading", "model": "…"}
{"type": "progress", "stage": "quantizing", "fraction": 0.42, "message": "層 12/28"}
{"type": "done", "output_dir": "/…", "size_bytes": 412345678, "bits_per_weight": 4.5}
```

`stage` は処理ごとに決める（`loading`、`converting`、`quantizing`、`merging`、`pruning`、`saving` など）。`fraction` は分からなければ null。

### `POST /forge/quantize`

```json
{"model": "mlx-community/Qwen3-0.6B-bf16", "output_dir": "/…/Models/qwen3-0.6b-3bit",
 "method": "affine", "bits": 3, "group_size": 64, "mixed": null, "overrides": [{"pattern": "lm_head", "bits": 8}]}
```

| 項目 | 内容 |
|---|---|
| `method: "affine"` | MLX の本物の量子化。`bits` は 2、3、4、5、6、8。`group_size` は 32、64、128 |
| `mixed` | 層ごとにビット数を変える、mlx-lm の決まった配分（`mixed_2_6`、`mixed_3_4`、`mixed_3_6`、`mixed_4_6`）。null なら使わない |
| `overrides` | 重みの名前（部分一致）ごとに、ビット数を上書きする。`bits` が null ならその重みは量子化しない |
| `method: "simulated"` | 量子化してすぐ戻した値を、ふつうの数（float16）で保存する。`bits` は 1〜8 の整数。`ternary: true` なら −1、0、+1 の 3 値（1.58 ビット）。本物の量子化にない、変わったビットの効き目を試すため |

元のモデルがすでに量子化されていれば、いったん戻してから量子化し直す。`done` の `bits_per_weight` は、重み 1 つあたりの平均のビット数。

### `POST /forge/convert`

Hugging Face の PyTorch や safetensors のモデル（transformers の形式）を、MLX の形式に変換する。

```json
{"model": "Qwen/Qwen3-0.6B", "output_dir": "/…", "dtype": "bfloat16", "quantize": {"bits": 4, "group_size": 64}}
```

`dtype` は `float16`、`bfloat16`、`float32`。`quantize` は null なら量子化しない。手元になければ 404（取り込みは `/models/download`）。

### `POST /forge/fuse`

LoRA のアダプタを本体に焼き込み、1 つのモデルにする。

```json
{"model": "…", "adapter": "/…/Adapters/名前", "output_dir": "/…", "dequantize": false}
```

### `POST /forge/merge`

同じ構造の 2 つのモデルを混ぜる。構造が違えば 422。

```json
{"models": ["…", "…"], "output_dir": "/…", "method": "slerp", "t": 0.5}
```

`method` は `linear`（`(1 − t)·A + t·B`）か `slerp`（球面の線形補間）。量子化されたモデルは戻してから混ぜ、float16 で保存する。

### `POST /forge/prune`

層やヘッドを抜いて、影響を見る。

```json
{"model": "…", "output_dir": "/…", "drop_layers": [20, 21], "drop_heads": [{"layer": 3, "head": 5}]}
```

- `drop_layers`: その層を取り除く（`num_hidden_layers` も減らす）
- `drop_heads`: その層の Attention のそのヘッドの出力を 0 にする（形は変えない）
- `done` に `num_layers` を足す

### `POST /forge/distill`

大きい先生モデルの出力の確率分布を、小さい生徒モデルに学ばせる（知識の蒸留）。語彙が違えば 422。

```json
{"teacher": "mlx-community/Qwen3-4B-Instruct-2507-4bit", "student": "mlx-community/Qwen3-0.6B-bf16",
 "texts": ["…"], "output_dir": "/…", "iterations": 200, "learning_rate": 1e-5, "temperature": 2.0, "alpha": 0.5,
 "max_seq_length": 512, "batch_size": 1, "lora_rank": 8}
```

- 損失は `alpha × KL(先生 ‖ 生徒, 温度 T) × T² + (1 − alpha) × 次のトークンの交差エントロピー`
- `lora_rank` があれば、生徒に LoRA を付けて学習し、`output_dir` にアダプタを書く。null なら生徒の全体を学習し、モデルとして書く
- 先生と生徒は同時にメモリに載せる（このときだけ、大きいモデル 1 つの決まりの例外）。学習が終わったら両方外す
- 進み具合: `{"type": "progress", "iteration", "total", "loss", "kl", "ce"}`、検証: `{"type": "validation", "iteration", "loss"}`、
  終わり: `{"type": "done", "output_dir", "kind": "adapter" | "model"}`

### `POST /forge/evaluate`（NDJSON）

いくつかのモデルを、同じ文章と同じプロンプトで比べる。

```json
{"models": [{"model": "…", "adapter": null}], "texts": ["…"], "prompts": ["…"], "max_tokens": 64, "seed": 0}
```

モデルごとに次の行を流し、最後に `{"type": "done"}`。

```
{"type": "loading", "model": "…"}
{"type": "result", "model": "…", "adapter": null, "perplexity": 12.3, "tokens": 5120, "seconds": 4.1,
 "tokens_per_second": 58.2, "size_bytes": 351000000, "peak_memory_bytes": 812000000, "samples": ["…"]}
```

`perplexity` は `texts` の続きを当てる難しさ（小さいほどよい）。`samples` は `prompts` への生成（同じ種）。

### Python のスクラッチ

エンジンの中で Python を実行する。ノートブックのように、同じ `session` の中では変数が残る。

`POST /scratch/run`（NDJSON）

```json
{"session": "b3f…", "code": "print(model.args.num_hidden_layers)", "model": "mlx-community/Qwen3-0.6B-4bit", "adapter": null}
```

| 名前 | 中身 |
|---|---|
| `model`、`tokenizer` | `model` を渡したときに載せたもの（mlx-lm） |
| `mx`、`nn`、`np`、`plt` | `mlx.core`、`mlx.nn`、`numpy`、`matplotlib.pyplot`（画面に出さない描き方） |
| `generate(prompt, **kwargs)` | 載せたモデルで生成した文字列を返す |
| `show(x)` | 図（matplotlib）、表（dict の list、または 2 次元の配列）、画像を出力に出す |

出力の行:

```
{"type": "stdout", "text": "28\n"}
{"type": "stderr", "text": "…"}
{"type": "image", "png_base64": "…"}
{"type": "table", "columns": ["層", "ノルム"], "rows": [[0, 1.2]]}
{"type": "value", "repr": "…"}          ← 最後の式の値（None でなければ）
{"type": "done", "seconds": 0.8}
{"type": "error", "message": "NameError: …", "traceback": "…"}
```

- `plt` で描いて `show(plt.gcf())` すると画像になる。実行の終わりに開いたままの図があれば、自動で画像にして閉じる
- 接続が切れたら実行を中断する
- `POST /scratch/reset` `{"session"}` → `{"reset": true}` 変数を消す
- 手元の Mac の上で、自分の書いたコードを動かすためのもの。エンジンは 127.0.0.1 とトークンでしか受け付けない
