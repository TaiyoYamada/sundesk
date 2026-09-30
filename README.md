# sundesk

[![CI](https://github.com/TaiyoYamada/sundesk/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/TaiyoYamada/sundesk/actions/workflows/ci.yml)
[![CodeQL](https://github.com/TaiyoYamada/sundesk/actions/workflows/codeql.yml/badge.svg?branch=develop)](https://github.com/TaiyoYamada/sundesk/actions/workflows/codeql.yml)

自分の知識グラフの上で、ローカル AI を動かし、覗き、いじるための macOS アプリ。

研究のノート、論文、実験の結果を一か所で読み書きし、そこから概念と関係の知識グラフを作り、
出典つきのチャットで問いに答える。Hugging Face のモデルを載せて、トークンの確率分布や
Attention を覗いたり、LoRA で学習させたり、量子化したり、画像を生成したりできる。

> [!NOTE]
> 個人のプロジェクトです。コードは参照のためだけに公開しており、利用は許諾していません（[LICENSE](LICENSE)）。

## できること

| 機能 | 内容 |
|---|---|
| ノート | Markdown（ライブプレビュー、ソース、閲覧）、HTML、コード、画像、PDF、Jupyter のノートブック。`[[リンク]]`、バックリンク、検索、タグ |
| 研究ライブラリ | ノート、論文、実験、データ、資料をフォルダの木で整理する。~/Research と study-artifact の研究のところは、その場で読む |
| 知識グラフ | ノートから用語と関係を抜き出し、Metal で描く。2D と 3D、経路、知識が育つ様子の再生 |
| チャット | 意味・語・知識グラフの 3 つで探し、出典つきで答える。Apple のオンデバイスモデルも選べる |
| 実験室 | Python のスクリプトでモデルを直接触る。次のトークンの確率、Attention、logit lens、活性、LoRA、steering |
| 工房 | 量子化、変換、合成、枝刈り、蒸留、評価 |
| 画像生成 | mflux（FLUX.2 klein 4B、Z-Image Turbo）。ビューア、比べる、お気に入り |

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
| `SampleLibrary/` | テストで使う、作り物の研究ライブラリ（[docs/library-format.md](docs/library-format.md)） |
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
