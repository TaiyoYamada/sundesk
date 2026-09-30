//
//  FileKindTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import Testing

@Suite("FileKind")
struct FileKindTests {
    @Test(
        "ファイル名から種類を決める",
        arguments: [
            ("固有値.md", FileKind.markdown),
            ("README.MARKDOWN", .markdown),
            ("レポート.html", .html),
            ("main.swift", .code(language: "swift")),
            ("attention.py", .code(language: "python")),
            ("config.yml", .code(language: "yaml")),
            ("Makefile", .code(language: "makefile")),
            ("メモ.txt", .text),
            ("図.PNG", .image),
            ("スライド.pdf", .pdf),
            ("解析.ipynb", .notebook),
            ("archive.zip", .other),
            ("拡張子なし", .other),
            (".gitignore", .other),
        ]
    )
    func kindFromFileName(name: String, expected: FileKind) {
        #expect(FileKind(fileName: name) == expected)
    }

    @Test("テキストとして開けるのは、Markdown、HTML、コード、テキスト、ノートブック")
    func sourceView() {
        for kind in [FileKind.markdown, .html, .code(language: "swift"), .text, .notebook] {
            #expect(kind.hasSourceView)
        }
        for kind in [FileKind.image, .pdf, .folder, .other] {
            #expect(!kind.hasSourceView)
        }
    }
}
