# 変更履歴

このプロジェクトの主な変更を記録する。書き方は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョンは [セマンティック バージョニング](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### 追加

- ノートの表示（フェーズ 1）
  - 画面を Xcode と Obsidian を合わせた構成にした: ナビゲータ（ファイル／検索／タグ）、タブで開くエディタ、インスペクタ
  - Markdown（数式、コード、表、注記、脚注、タスクリスト、`[[リンク]]`）、HTML、テキスト、コード、画像、PDF を開ける
  - 表示とソースを ⌘E で切り替える。ソースは行番号と色づけつき
  - `[[リンク]]` と相対リンクをたどると、そのファイルを新しいタブで開く
  - インスペクタに、ファイルの情報、プロパティ、タグ、目次、バックリンクを出す
  - ノートの索引（SwiftData）: タイトル、タグ、リンク、本文。変わったノートだけを読み直す
  - Vault の変更を FSEvents で見張り、自動で読み直す
  - 設定に Vault の場所を追加した
  - モックの Vault（`SampleVault/`）: 数学、量子計算、Swift、機械学習、論文メモ、研究ログ、資料（画像、PDF、JSON、テキスト）
  - 描画用の `renderer/`（TypeScript: markdown-it、KaTeX、Shiki）と、CI の Renderer ジョブ
  - ADR 0008、0009

- アプリの外枠: サイドバー（ノート、知識グラフ、チャット、実験室、画像生成、モデル）、
  ツールバーのエンジン状態、「エンジン」メニュー、設定ウインドウ
- Python の AI エンジン（FastAPI）: 死活確認、起動ごとのトークン認証、親プロセスの見張り
- エンジンの起動と停止: アプリの起動時に自動で立ち上げ、終了時に止める。
  アプリが強制終了されても、エンジンが自分で終了する
- Clean Architecture の Swift パッケージ（Domain、Engine、Data、Presentation、Composition）
- DI コンテナ（Factory）
- 開発環境: xcconfig、Makefile、SwiftLint、swift-format、ruff、pyright、actionlint
- CI（GitHub Actions）、CodeQL（Python と Actions）、Dependabot、Issue とプルリクエストのテンプレート
- 要件、アーキテクチャ、ADR 0001〜0007

### 削除

- 最初の試作コード（Obsidian 型の Vault）
