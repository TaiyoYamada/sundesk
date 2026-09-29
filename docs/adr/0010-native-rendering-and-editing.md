# 0010. ノートの描画と編集は Swift で行い、WebKit は HTML ファイルだけに使う

- 状態: 採用（[0008](0008-webkit-renderer.md) を置き換える）
- 日付: 2026-09-29

## 背景

[ADR 0008](0008-webkit-renderer.md) では、Markdown とコードを WebKit の中の JavaScript（markdown-it、KaTeX、Shiki）で描いていた。
その後、次の要望が加わった。

- 描画は、なるべく Swift と Apple 公式のものを使う
- ノートを sundesk の中で編集する。Obsidian のように、ライブプレビュー、ソース、閲覧の 3 つのモードを持ち、自動で保存する

WebKit の中の描画では、編集（カーソル、取り消し、日本語入力）を JavaScript 側で作ることになり、
規則（`[[リンク]]` の判定など）も Swift と TypeScript の二か所に分かれていた。

## 決定

| 用途 | 使うもの |
|---|---|
| Markdown の解析 | **swift-markdown**（swiftlang。cmark-gfm を使う） |
| 閲覧モード | **SwiftUI**（ブロックごとの View。表は `Grid`、リンクは `OpenURLAction`） |
| 編集（ライブプレビュー、ソース、コード） | **TextKit 2** の `NSTextView` |
| 数式 | **SwiftMath**（LaTeX を画像にする。公式のものがないため） |
| コードの色づけ | **swift-tree-sitter**（言語ごとの文法パッケージ。公式のものがないため） |
| HTML ファイル | WebKit（SwiftUI の `WebView`。`sundesk-vault:` のスキームで Vault の中だけを読む） |
| 画像、PDF、その他 | SwiftUI、PDFKit、Quick Look（変更なし） |

- Markdown は `SundeskMarkdown` で 3 通りに読む
  - `SwiftMarkdownParser`: 索引用（タイトル、タグ、リンク、見出し）
  - `MarkdownDocumentParser`: 閲覧用のブロックの木
  - `MarkdownSyntax`: エディタ用の記法の範囲（UTF-16 の範囲）
- 数式と `[[リンク]]` は CommonMark にないので、解析の前に伏せる（閲覧用は目印の文字に置き換え、エディタ用は空白にして位置を保つ）
- ライブプレビューは、カーソルのない段落の記号（`#`、`**`、`[[` など）を、ごく小さい透明な文字にして隠す
- 編集した本文は 1 秒待ってから自動で保存する。タブを閉じるとき、アプリを終了するとき、⌘S では待たずに保存する
- 日本語の変換中（未確定の文字があるとき）は、色づけも保存もしない

## 検討した選択肢

| 選択肢 | 良い点 | 悪い点 |
|---|---|---|
| **Swift で描画と編集（この決定）** | 公式の部品が中心。規則が Swift の一か所にまとまる。編集が自然（取り消し、検索、日本語入力） | 数式とコードの色づけは外部のパッケージに頼る。見た目を自分で整える |
| WebKit + JavaScript のまま（0008） | 数式とコードの見た目が成熟している | 編集を JavaScript で作ることになる。規則が二か所に分かれる |
| WebKit の中で CodeMirror を使う | Obsidian と同じ編集の感触 | Swift から遠い。JavaScript の依存が増える |

## 結果

- `renderer/`（TypeScript）、Node.js、CI の Renderer ジョブ、npm の Dependabot をなくした
- ライブプレビューで、数式はソースのまま色を変えて見せる（画像にするのは閲覧モードだけ）
- tree-sitter の文法のうち 4 つ（CSS、JavaScript、Python、YAML）は、SwiftPM 6.4 で外部スキャナがビルドされない。
  `TreeSitterScanners` に `scanner.c` を写して補い、文法のバージョンを固定している（`Sources/Infrastructure/TreeSitterScanners/README.md`）
