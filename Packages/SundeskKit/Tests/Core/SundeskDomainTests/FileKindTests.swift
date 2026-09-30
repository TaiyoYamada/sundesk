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

    @Test("Markdown と HTML は、表示とソースの両方を持つ")
    func markdownAndHTMLHaveBothViews() {
        for kind in [FileKind.markdown, .html] {
            #expect(kind.hasRenderedView)
            #expect(kind.hasSourceView)
        }
    }

    @Test("コードはソースだけ、画像と PDF は表示だけ")
    func codeIsSourceOnlyAndImagesAreRenderedOnly() {
        #expect(!FileKind.code(language: "swift").hasRenderedView)
        #expect(FileKind.code(language: "swift").sourceLanguage == "swift")
        #expect(FileKind.image.hasRenderedView && !FileKind.image.hasSourceView)
        #expect(FileKind.pdf.sourceLanguage == nil)
    }
}
