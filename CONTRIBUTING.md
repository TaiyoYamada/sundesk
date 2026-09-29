# 開発の進め方

sundesk は個人のプロジェクトです。外部からのコントリビューション（プルリクエストや
Issue）は受け付けていません。この文書は、自分と開発を手伝う AI エージェントのための
作業手順です。利用条件は [LICENSE](LICENSE) を参照してください。

## ブランチ（git flow）

| ブランチ | 役割 | 作る元 | 取り込む先 |
|---|---|---|---|
| `main` | リリース済みの状態。タグ `vX.Y.Z` を打つ | — | — |
| `develop` | 次のリリースに向けた統合先 | `main` | — |
| `feature/<issue番号>-<内容>` | 機能の開発 | `develop` | `develop` |
| `release/X.Y.Z` | リリースの準備（バージョン番号、CHANGELOG） | `develop` | `main` と `develop` |
| `hotfix/X.Y.Z` | リリース済みの版の緊急修正 | `main` | `main` と `develop` |

- `main` と `develop` には直接コミットしない。必ずプルリクエストを通す
- プルリクエストは CI が通ってから取り込む
- 例: `feature/12-knowledge-graph-renderer`

## コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/ja/v1.0.0/) の形式に従う。
**種類は英語、要約と本文は日本語**で書く。

```
<種類>(<範囲>): <要約>

<本文（任意）>

<フッター（任意）>
```

例:

```
feat(graph): 知識グラフの力学レイアウトを Metal で計算する
fix(rag): 出典の番号がずれる問題を直す
docs: アーキテクチャの図を更新する
```

| 種類 | 使う場面 |
|---|---|
| `feat` | 機能の追加 |
| `fix` | 不具合の修正 |
| `docs` | 文書だけの変更 |
| `style` | 動作に影響しない書式の変更 |
| `refactor` | 機能を変えないコードの整理 |
| `perf` | 性能の改善 |
| `test` | テストの追加や修正 |
| `build` | ビルドの仕組みや依存関係の変更 |
| `ci` | CI の設定の変更 |
| `chore` | その他の雑務 |
| `revert` | 以前のコミットの取り消し |

- 範囲（任意）は、モジュールや機能の名前にする（`domain`、`data`、`graph`、`rag`、`lab`、`image`、`engine`、`app` など）
- 要約は「〜する」で終える。句点は付けない
- 互換性を壊す変更は、`feat!:` のように `!` を付け、フッターに `BREAKING CHANGE:` と書く

## バージョン

[セマンティック バージョニング](https://semver.org/lang/ja/)に従う。変更の記録は
`CHANGELOG.md` に [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式で残す。

## 開発環境

- macOS 27、Xcode 27（Swift 6.4）
- Python の環境は [uv](https://docs.astral.sh/uv/) で管理する

よく使う操作は Makefile にまとめてある。`make` だけで一覧が出る。

```sh
make bootstrap   # 開発に必要な道具と依存関係をそろえる
make lint        # SwiftLint、swift-format、ruff、pyright、actionlint
make format      # 自動で整形する
make test        # Swift と Python のテスト（UI テストを除く）
make test-ui     # UI テスト
make engine      # AI エンジンだけを単独で起動する
```

## コードの書き方

- Swift ファイルの先頭には、Xcode の形式でヘッダーを書く。2 行目はファイルが属するターゲット名（`sundesk`、`SundeskDomain` など）、作成者は `山田大陽`、日付はファイルを作った日にする

  ```swift
  //
  //  ChatViewModel.swift
  //  SundeskPresentation
  //
  //  Created by 山田大陽 on 2026/09/29.
  //
  ```

- 設計は [docs/architecture.md](docs/architecture.md) に従う（Clean Architecture + MVVM）
- 大きな設計判断は ADR として `docs/adr/` に残す
- 実装したらテストも書く。プルリクエストにはテストを含める
