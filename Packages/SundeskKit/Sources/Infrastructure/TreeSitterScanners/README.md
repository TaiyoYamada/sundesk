# TreeSitterScanners

tree-sitter の文法パッケージのうち、CSS、JavaScript、Python、YAML の 4 つは、
`Package.swift` で外部スキャナ（`src/scanner.c`）を次のように読み込んでいる。

```swift
if FileManager.default.fileExists(atPath: "src/scanner.c") {
    sources.append("src/scanner.c")
}
```

Swift 6.4 の SwiftPM は `Package.swift` をパッケージのフォルダ以外で評価するので、
この判定が常に偽になり、`scanner.c` がビルドから漏れてリンクに失敗する
（2026-09 時点で、各リポジトリの main でも直っていない）。

そこで、漏れる `scanner.c`（と、それが使うヘッダー）だけをここに写し、
別のモジュールとしてビルドして足りない関数を補う。本体の `parser.c` は各パッケージのまま使う。

| 言語 | 写した元 | バージョン | ライセンス |
|---|---|---|---|
| CSS | tree-sitter/tree-sitter-css | 0.25.0 | MIT（`css/LICENSE`） |
| JavaScript | tree-sitter/tree-sitter-javascript | 0.25.0 | MIT（`javascript/LICENSE`） |
| Python | tree-sitter/tree-sitter-python | 0.25.0 | MIT（`python/LICENSE`） |
| YAML | tree-sitter-grammars/tree-sitter-yaml | 0.7.2 | MIT（`yaml/LICENSE`） |

**文法のバージョンを上げるときは、ここの `scanner.c` も同じバージョンのものに差し替えること。**
食い違うと、動作がおかしくなったり落ちたりする。そのため `Package.swift` では、
この 4 つのバージョンを完全に固定している。

上流で直ったら（`Context.packageDirectory` を使う形になったら）、このモジュールは消してよい。
