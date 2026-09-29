# 変更履歴

このプロジェクトの主な変更を記録する。書き方は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョンは [セマンティック バージョニング](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### 追加

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
