//
//  MarkdownChunkerTests.swift
//  SundeskMarkdownTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import SundeskMarkdown
import Testing

@Suite("MarkdownChunker")
struct MarkdownChunkerTests {
    @Test("見出しで区切り、見出しの階層と行番号を持つ")
    func splitsByHeadings() {
        let source = """
            ---
            title: 固有値
            ---
            # 固有値

            前置き。

            ## 定義

            固有値とは、$A v = \\lambda v$ を満たす数である。

            ### 例

            対角行列の [[対角成分|成分]]。

            ```swift
            let x = 1
            ```
            """

        let chunks = MarkdownChunker().chunks(for: source, path: "数学/固有値.md", title: "固有値")

        #expect(chunks.map(\.headingPath) == [["固有値"], ["固有値", "定義"], ["固有値", "定義", "例"]])
        #expect(chunks.map(\.id) == ["数学/固有値.md#0", "数学/固有値.md#1", "数学/固有値.md#2"])
        #expect(chunks.map(\.line) == [6, 10, 14])
        #expect(chunks[1].text.contains("$A v = \\lambda v$"))
        #expect(chunks[1].plainText == "固有値とは、 を満たす数である。")
        #expect(chunks[2].plainText == "対角行列の 成分。")
    }

    @Test("見出しだけの節は捨てる")
    func dropsEmptySections() {
        let chunks = MarkdownChunker().chunks(for: "# A\n## B\n## C\n本文", path: "a.md", title: "A")

        #expect(chunks.map(\.headingPath) == [["A", "C"]])
    }

    @Test("長い節は段落の切れ目で分ける")
    func splitsLongSections() {
        let paragraph = String(repeating: "あ", count: 60)
        let source = "# A\n\n" + (0..<5).map { _ in paragraph }.joined(separator: "\n\n")

        let chunks = MarkdownChunker(maxLength: 100).chunks(for: source, path: "a.md", title: "A")

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.headingPath == ["A"] })
        #expect(chunks.map(\.line) == chunks.map(\.line).sorted())
    }
}
