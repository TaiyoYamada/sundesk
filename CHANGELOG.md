# 変更履歴

このプロジェクトの主な変更を記録する。書き方は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョンは [セマンティック バージョニング](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### 追加

- 知識グラフ（フェーズ 2）: ノートから用語と関係を抜き出し、PageRank とコミュニティで色と大きさを付けて Metal で描く
- ノートを根拠に答えるチャット（フェーズ 3）: 3 つの検索の組み合わせ、出典つきの回答、会話の履歴。Apple のオンデバイスモデルも選べる
- LLM の実験室（フェーズ 4）: トークン、次のトークンの確率、確率つきの生成、Attention、logit lens、活性。実行の記録
- モデルの管理: Hugging Face からの取り込み、削除、メモリから外す
- 画像生成（フェーズ 5）: mflux で FLUX.2 klein 4B と Z-Image Turbo を動かす
- いじる（フェーズ 6）: ノートで LoRA を学習する、steering で生成の向きを変える
- エンジンの API（docs/engine-api.md）、ADR 0012、0013
- ノートの表示（フェーズ 1）
  - 画面を Xcode と Obsidian を合わせた構成にした: ナビゲータ（ファイル／検索／タグ）、タブで開くエディタ、インスペクタ
  - Markdown（数式、コード、表、注記、脚注、タスクリスト、`[[リンク]]`）、HTML、テキスト、コード、画像、PDF を開ける
  - Markdown はライブプレビュー、ソース、閲覧の 3 つのモードで開き、⌘E で編集と閲覧を切り替える
  - ノートとコードを編集できる（TextKit 2）。1 秒ごとに自動で保存し、タブを閉じるとき、⌘S、終了時にも保存する
  - 閲覧モードは SwiftUI で描く（数式は SwiftMath、コードの色づけは tree-sitter の 15 言語）
  - `[[リンク]]` と相対リンクをたどると、そのファイルを新しいタブで開く
  - インスペクタに、ファイルの情報、プロパティ、タグ、目次、バックリンクを出す
  - ノートの索引（SwiftData）: タイトル、タグ、リンク、本文。変わったノートだけを読み直す
  - Vault の変更を FSEvents で見張り、自動で読み直す
  - 設定に Vault の場所を追加した
  - モックの Vault（`SampleVault/`）: 数学、量子計算、Swift、機械学習、論文メモ、研究ログ、資料（画像、PDF、JSON、テキスト）
  - ADR 0008〜0011

### 変更

- 描画を WebKit の JavaScript（markdown-it、KaTeX、Shiki）から、Swift（swift-markdown、SwiftUI、TextKit 2）に移した。
  WebKit は HTML ファイルだけに使う（ADR 0010）
- Swift パッケージを機能ごとのマルチモジュール（App / Features / Core / Infrastructure / UI）にし、
  アプリのターゲットは起動だけにした（ADR 0011）

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
- 描画用の `renderer/`（TypeScript）と、CI の Renderer ジョブ
