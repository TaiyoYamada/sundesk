# sundesk

[![CI](https://github.com/TaiyoYamada/sundesk/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/TaiyoYamada/sundesk/actions/workflows/ci.yml)
[![CodeQL](https://github.com/TaiyoYamada/sundesk/actions/workflows/codeql.yml/badge.svg?branch=develop)](https://github.com/TaiyoYamada/sundesk/actions/workflows/codeql.yml)

自分の知識グラフの上で、ローカル AI を動かし、覗き、いじるための macOS アプリ。

学習・研究ノート（Markdown）を取り込み、概念と関係の知識グラフを作り、
出典つきの RAG で問いに答える。Hugging Face のモデルを載せて、トークンの確率分布や
Attention を覗いたり、LoRA で学習させたり、画像を生成したりできる場所を目指している。

> [!NOTE]
> 個人のプロジェクトです。コードは参照のためだけに公開しており、利用は許諾していません（[LICENSE](LICENSE)）。

## 状態

フェーズ 0〜6 の最初の形ができた。使いながら直していく。

| フェーズ | 内容 | 状態 |
|---|---|---|
| 0 | 基盤（開発環境、CI、アプリの外枠、エンジン） | 完了 |
| 1 | ノートの表示と編集（ライブプレビュー、ソース、閲覧）と索引 | 完了 |
| 2 | 知識グラフ（Metal で描画） | 完了 |
| 3 | RAG（出典つきのチャット） | 完了 |
| 4 | LLM 実験室（確率分布、Attention、logit lens、活性） | 完了 |
| 5 | 画像生成（mflux） | 完了 |
| 6 | LoRA、steering | 完了 |

## 構成

```
┌─ sundesk.app（Swift / SwiftUI）──────────────────────┐
│  画面 ／ SwiftData ／ Metal ／ エンジンの起動と停止         │
└───────────────┬──────────────────────────────────────┘
                │ 127.0.0.1 の HTTP（起動ごとのトークン）
┌───────────────┴──────────── engine（Python）───────────┐
│  LLM ／ 画像生成 ／ 埋め込み ／ 形態素解析 ／ グラフの計算    │
└──────────────────────────────────────────────────────┘
```

| フォルダ | 中身 |
|---|---|
| `sundesk/` | アプリのターゲット（起動するだけ） |
| `Packages/SundeskKit/` | アプリのすべて。App / Features / Core / Infrastructure / UI のモジュール |
| `engine/` | Python の AI エンジン（uv で管理） |
| `tools/sundesk-log/` | 実験のスクリプトから結果を取り込み箱へ書く記録用ライブラリ（Python） |
| `SampleLibrary/` | 研究ライブラリの見本（論文、実験、データ、ノート。[docs/library-format.md](docs/library-format.md)） |
| `Configurations/` | ビルド設定（xcconfig） |
| `docs/` | 要件、アーキテクチャ、ADR |

詳しくは [docs/architecture.md](docs/architecture.md) と [docs/adr/](docs/adr/README.md)。

## 必要なもの

- Apple シリコンの Mac（メモリ 16GB 以上）
- macOS 27、Xcode 27（Swift 6.4）
- [Homebrew](https://brew.sh)（SwiftLint、uv、actionlint を入れるため）

## はじめかた

```sh
make bootstrap   # 道具と依存関係をそろえる
make run         # ビルドして起動する
make install     # Release でビルドし、/Applications に入れ直して起動する
```

起動すると、アプリが Python エンジンを自動で立ち上げる（初回は依存関係の取得で少し時間がかかる）。

## 開発

`make` だけで、使える操作の一覧が出る。

```sh
make lint        # SwiftLint、swift-format、ruff、pyright、actionlint
make format      # 自動で整形する
make test        # UI テスト以外のすべてのテスト
make test-ui     # UI テスト
make coverage    # Swift パッケージのカバレッジ
make engine      # エンジンだけを単独で起動する
```

ブランチ、コミットメッセージ、コードの書き方は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。
