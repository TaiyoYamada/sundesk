# 開発メモ

sundesk は個人のプロジェクトなので、外部からのプルリクエストや Issue は受け付けていません。
利用条件は [LICENSE](LICENSE) にあります。ここには、自分が開発するときの決め事をまとめています。

## ブランチ

git flow で運用しています。`main` はリリース済みの状態、`develop` は次のリリースに向けた統合先です。
機能は `develop` から `feature/<番号>-<内容>` を切って作り、プルリクエストで `develop` に戻します。
`main` と `develop` には直接コミットしません。

## コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/ja/v1.0.0/) に沿って、種類は英語、要約は日本語で書いています。

```
feat(graph): 知識グラフの力学レイアウトを Metal で計算する
fix(rag): 出典の番号がずれる問題を直す
docs: アーキテクチャの図を更新する
```

範囲にはモジュールや機能の名前（`notes`、`editor`、`graph`、`rag`、`lab`、`image`、`engine` など）を入れます。

## バージョン

[セマンティック バージョニング](https://semver.org/lang/ja/)で番号を付け、変更は `CHANGELOG.md` に残しています。

## 開発環境

macOS 27 と Xcode 27（Swift 6.4）を使っています。Python の環境は [uv](https://docs.astral.sh/uv/) で管理しています。
よく使う操作は Makefile にまとめてあり、`make` だけで一覧が出ます。

```sh
make bootstrap   # 道具と依存関係をそろえる
make lint        # 静的チェック
make format      # 整形
make test        # UI テスト以外のテスト
make test-ui     # UI テスト
make engine      # AI エンジンだけを起動する
```

## コード

設計は [docs/architecture.md](docs/architecture.md) にまとめています。大きな判断をしたときは、理由を
[docs/adr/](docs/adr/README.md) に残しています。Swift ファイルの先頭には Xcode が作る形のヘッダーを付けています。
