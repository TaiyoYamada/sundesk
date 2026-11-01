# sundesk

[![CI](https://github.com/TaiyoYamada/sundesk/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/TaiyoYamada/sundesk/actions/workflows/ci.yml)
[![CodeQL](https://github.com/TaiyoYamada/sundesk/actions/workflows/codeql.yml/badge.svg?branch=develop)](https://github.com/TaiyoYamada/sundesk/actions/workflows/codeql.yml)

論文を集め、読み、書き込み、LaTeX から引くための、自分専用の文献管理アプリ（macOS）。
Zotero のような文献管理を、Swift と SwiftUI だけで作っている。

> [!NOTE]
> 個人のプロジェクトです。コードは参照のためだけに公開しており、利用は許諾していません（[LICENSE](LICENSE)）。

## できること

| 機能 | 内容 |
|---|---|
| 登録 | DOI、arXiv の ID、ISBN から書誌情報を引いて足す（arXiv は PDF も取る）。PDF のドロップ、手での入力 |
| 整理 | 入れ子のコレクション、タグ、読んだ状態、検索 |
| 読む | PDF のハイライト（5 色）とコメント、文献ごとの Markdown のメモ |
| 要約 | Apple のオンデバイスモデルで、PDF を目的、手法、結果、限界にまとめる |
| 書き出し | BibTeX のコピーと .bib への書き出し。引用キーは自動で付ける |

## 構成

| フォルダ | 中身 |
|---|---|
| `sundesk/` | アプリのターゲット（起動するだけ） |
| `Packages/SundeskKit/` | アプリのすべて。App / Features / Core / Infrastructure / UI のモジュール |
| `Configurations/` | ビルド設定（xcconfig） |
| `docs/` | 要件、アーキテクチャ、ADR |

文献の情報、注釈、メモは `~/Library/Application Support/com.taiyou.sundesk/Library/library.store`（SwiftData）に、
PDF は同じフォルダの `Storage/` に置く。外と通信するのは、書誌情報と arXiv の PDF を取るときだけ。

詳しくは [docs/architecture.md](docs/architecture.md) と [docs/adr/](docs/adr/README.md)。

## 必要なもの

- Apple シリコンの Mac。要約には Apple Intelligence が要る
- macOS 27、Xcode 27（Swift 6.4）
- [Homebrew](https://brew.sh)（SwiftLint、actionlint を入れるため）

## はじめかた

```sh
make bootstrap   # 道具と依存関係をそろえる
make run         # ビルドして起動する
make install     # Release でビルドし、/Applications に入れ直して起動する
```

## 開発

`make` だけで、使える操作の一覧が出る。

```sh
make lint        # SwiftLint、swift-format、actionlint
make format      # 自動で整形する
make test        # UI テスト以外のすべてのテスト
make test-ui     # UI テスト
make coverage    # Swift パッケージのカバレッジ
```

ブランチ、コミットメッセージ、コードの書き方は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。
