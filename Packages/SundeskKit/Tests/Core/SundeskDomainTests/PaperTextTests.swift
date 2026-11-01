//
//  PaperTextTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Testing

@testable import SundeskDomain

@Suite("要約のための本文の区切り方")
struct PaperTextTests {
    @Test("参考文献の節から後ろを落とす（1 ページ目の目次は無視する）")
    func body() {
        let pages = ["Title\nReferences\nAbstract", "Introduction\nMethod", "Results\n5. References\n[1] A", "[2] B"]
        #expect(PaperText.body(of: pages) == ["Title\nReferences\nAbstract", "Introduction\nMethod", "Results"])
        #expect(PaperText.body(of: ["本文", "結論\n参考文献\n[1] A"]) == ["本文", "結論"])
        #expect(PaperText.body(of: ["本文", "結論"]) == ["本文", "結論"])
    }

    /// 文字数をトークン数とみなす。
    private func count(_ text: String) async throws(SummaryError) -> Int {
        text.count
    }

    @Test("上限まで、ページを順に詰める")
    func packing() async throws {
        let parts = try await PaperText.parts(of: ["aaaa", "bbb", "cc", "", "d"], budget: 7, tokenCount: count)
        #expect(parts == ["aaaa\nbbb", "cc\nd"])
    }

    @Test("上限を超えるページは、行で半分に分ける")
    func splitting() async throws {
        let parts = try await PaperText.parts(of: ["aaa\nbbb\nccc\nddd"], budget: 8, tokenCount: count)
        #expect(parts == ["aaa\nbbb", "ccc\nddd"])
        #expect(parts.allSatisfy { $0.count <= 8 })
    }

    @Test("改行のない長い文は、文字で分ける")
    func splittingLongLine() async throws {
        let parts = try await PaperText.parts(of: [String(repeating: "あ", count: 10)], budget: 4, tokenCount: count)
        #expect(parts.joined() == String(repeating: "あ", count: 10))
        #expect(parts.allSatisfy { $0.count <= 4 })
    }
}
