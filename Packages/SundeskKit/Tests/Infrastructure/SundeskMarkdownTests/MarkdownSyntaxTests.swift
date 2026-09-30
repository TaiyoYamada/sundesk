//
//  MarkdownSyntaxTests.swift
//  SundeskMarkdownTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskMarkdown
import Testing

@Suite("MarkdownSyntax")
struct MarkdownSyntaxTests {
    /// 範囲を文字列に直して比べやすくする。
    private func spans(_ source: String, path: String = "数学/固有値.md") -> [(String, MarkdownSyntaxRole)] {
        MarkdownSyntax.spans(in: source, notePath: path).map {
            ((source as NSString).substring(with: $0.range), $0.role)
        }
    }

    private func texts(_ source: String, role: MarkdownSyntaxRole) -> [String] {
        spans(source).filter { $0.1 == role }.map(\.0)
    }

    @Test("見出しの # は記号として分ける（日本語でも位置がずれない）")
    func heading() {
        let result = spans("前置き\n## 固有値の定義")

        #expect(result.contains { $0 == ("## 固有値の定義", .heading(level: 2)) })
        #expect(result.contains { $0 == ("## ", .syntax) })
    }

    @Test("フロントマターの後ろでも位置が合う")
    func afterFrontmatter() {
        let source = "---\ntitle: 固有値\n---\n**強調**"

        #expect(texts(source, role: .frontmatter) == ["---\ntitle: 固有値\n---\n"])
        #expect(texts(source, role: .strong) == ["**強調**"])
        #expect(texts(source, role: .syntax) == ["**", "**"])
    }

    @Test("強調、斜体、打ち消し、インラインコードの記号")
    func inlineSyntax() {
        let source = "*斜体* ~~消す~~ `code`"

        #expect(texts(source, role: .emphasis) == ["*斜体*"])
        #expect(texts(source, role: .strikethrough) == ["~~消す~~"])
        #expect(texts(source, role: .inlineCode) == ["`code`"])
        #expect(texts(source, role: .syntax) == ["*", "*", "~~", "~~", "`", "`"])
    }

    @Test("リンクは文字だけを残し、[ と ](...) を記号にする")
    func links() {
        let result = spans("[量子ビット](../量子計算/量子ビット.md)")

        #expect(result.contains { $0 == ("量子ビット", .link(.vault("量子計算/量子ビット.md"))) })
        #expect(result.filter { $0.1 == .syntax }.map(\.0) == ["[", "](../量子計算/量子ビット.md)"])
    }

    @Test("[[リンク|表示名]] は表示名だけを残す")
    func wikilinks() {
        let source = "[[線形代数#固有値|固有値の節]] と [[量子ビット]]"

        #expect(texts(source, role: .wikilink(target: "線形代数")) == ["固有値の節"])
        #expect(texts(source, role: .wikilink(target: "量子ビット")) == ["量子ビット"])
        #expect(texts(source, role: .syntax) == ["[[線形代数#固有値|", "]]", "[[", "]]"])
    }

    @Test("数式の中の _ を斜体として読まない")
    func mathIsNotEmphasis() {
        let source = "$a_i$ と $b_j$、$$\nx^2\n$$"

        #expect(texts(source, role: .math(display: false)) == ["$a_i$", "$b_j$"])
        #expect(texts(source, role: .math(display: true)) == ["$$\nx^2\n$$"])
        #expect(texts(source, role: .emphasis).isEmpty)
    }

    @Test("コードブロックはフェンスと中身に分け、言語を持つ")
    func codeBlock() {
        let source = "```swift\nlet a = \"$x$ #tag\"\n```\n"
        let result = spans(source)

        #expect(result.filter { $0.1 == .codeFence }.map(\.0) == ["```swift", "```"])
        #expect(result.contains { $0 == ("let a = \"$x$ #tag\"", .codeBlock(language: "swift")) })
        #expect(result.allSatisfy { $0.1 != .tag && $0.1 != .math(display: false) })
    }

    @Test("リスト、タスク、引用の記号")
    func blockMarkers() {
        let source = "- [x] 済んだ\n1. 番号\n\n> 引用\n> 続き"

        #expect(texts(source, role: .listMarker) == ["- ", "1. "])
        #expect(texts(source, role: .taskMarker(checked: true)) == ["[x]"])
        #expect(texts(source, role: .quoteMarker) == ["> ", "> "])
    }

    @Test("表の区切り")
    func table() {
        let source = "| a | b |\n| --- | --- |\n| 1 | 2 |"

        #expect(texts(source, role: .tableDelimiter) == ["|", "|", "|", "| --- | --- |", "|", "|", "|"])
    }

    @Test("本文のタグ")
    func tags() {
        #expect(texts("メモ #線形代数", role: .tag) == ["#線形代数"])
    }
}
