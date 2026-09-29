# 0008. ノートの描画は WebKit の中で markdown-it、KaTeX、Shiki を使う

- 状態: 採用
- 日付: 2026-09-29

## 背景

学習ノートは数式（インラインとディスプレイ）、コード、表、注記、`[[リンク]]` を多く含む。
Markdown、HTML、テキスト、コードを「表示」と「生のソース」の両方で見たい。
見やすくて簡素な描画にしたい、という要望がある。

## 決定

- Markdown、HTML、テキスト、コードは、アプリの中の WebKit（SwiftUI の `WebView` と `WebPage`）で描く
- 描画には次の JavaScript ライブラリを使い、`renderer/`（TypeScript）で 1 つのファイルにまとめてアプリに同梱する
  - Markdown: **markdown-it**（数式、脚注、タスクリストは `@mdit` のプラグイン）
  - 数式: **KaTeX**
  - コードの色づけ: **Shiki**（ライトとダークの色を CSS 変数で持つ）
- `[[リンク]]` と注記（`> [!note] 見出し`）は Obsidian と同じ書き方に合わせ、プラグインを自作する
- ソース表示も Shiki で色づけし、行番号を付ける
- 画像は SwiftUI、PDF は PDFKit、それ以外は Quick Look で表示する（WebKit を使わない）
- ページとアプリの間は独自の URL スキームでつなぐ
  - `sundesk-app:` 同梱した renderer
  - `sundesk-vault:` Vault のファイル
  - `sundesk-open:` ノートを開く指示
  - `file://` は使わず、決めたフォルダの外は読めないようにする
- ページは外部と通信しない（Content-Security-Policy で禁止する）

## 検討した選択肢

| 選択肢 | 良い点 | 悪い点 |
|---|---|---|
| **WebKit + markdown-it + KaTeX + Shiki** | 数式とコードの描画が最も成熟している。拡張しやすい | JavaScript（約 2.7MB）を同梱する。Swift と JavaScript の二か所に規則がある |
| marked + temml（study のサイトと同じ） | サイトと見た目がそろう | 数式の見た目は KaTeX のほうが LaTeX に近い |
| SwiftUI だけで描く（swift-markdown など） | ネイティブで軽い | 数式とコードの色づけを自前で作ることになる |

## 結果

- 数式、コード、表の見た目がよく、ライトとダークにも追従する
- `[[リンク]]` の判定（コードと数式の中は除く）は、索引用の Swift（`MarkdownAnalyzer`）と
  描画用の TypeScript の二か所にある。変えるときは両方を直し、両方のテストを通す
- renderer のビルド結果はコミットする。CI で、ソースからビルドし直した結果と一致するか確かめる
