//
//  CodeHighlighterTests.swift
//  SundeskCodeHighlightTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskCodeHighlight
import Testing

@Suite("CodeHighlighter", .timeLimit(.minutes(1)))
struct CodeHighlighterTests {
    private let highlighter = CodeHighlighter()

    private func kinds(_ code: String, _ language: String) -> [String: CodeTokenKind] {
        let text = code as NSString
        var result: [String: CodeTokenKind] = [:]
        for token in highlighter.highlight(code, language: language) {
            result[text.substring(with: token.range)] = token.kind
        }
        return result
    }

    @Test("Swift のキーワード、文字列、コメントに色を付ける")
    func highlightsSwift() {
        let tokens = kinds("let greeting = \"こんにちは\" // あいさつ", "swift")

        #expect(tokens["let"] == .keyword)
        #expect(tokens["こんにちは"] == .string)  // Swift の文法は、引用符と中身を別々に分類する
        #expect(tokens["// あいさつ"] == .comment)
    }

    @Test(
        "主な言語で、何かしら色が付く",
        arguments: [
            ("python", "def f(x):\n    return x + 1  # 足す"),
            ("javascript", "const x = () => 42;"),
            ("typescript", "const x: number = 1;"),
            ("tsx", "const a = <div className=\"x\">hi</div>;"),
            ("json", "{\"a\": [1, true, null]}"),
            ("html", "<p class=\"x\">本文</p>"),
            ("css", "body { color: red; }"),
            ("bash", "echo \"$HOME\" # コメント"),
            ("rust", "fn main() { let x = 1; }"),
            ("go", "package main\nfunc main() {}"),
            ("c", "int main(void) { return 0; }"),
            ("cpp", "class A { public: int x; };"),
            ("java", "class A { void f() {} }"),
            ("yaml", "key: value # コメント"),
        ]
    )
    func highlightsMainLanguages(language: String, code: String) {
        #expect(!highlighter.highlight(code, language: language).isEmpty, "\(language) に色が付かない")
    }

    @Test("別名を受け付け、知らない言語は色を付けない")
    func aliasesAndUnknown() {
        #expect(!highlighter.highlight("x = 1", language: "py").isEmpty)
        #expect(!highlighter.highlight("echo a", language: "sh").isEmpty)
        #expect(!highlighter.highlight("key: value", language: "yml").isEmpty)
        #expect(highlighter.highlight("+++", language: "brainfuck").isEmpty)
    }

    @Test("日本語を含んでも、範囲は UTF-16 でずれない")
    func rangesAreUTF16() {
        let code = "// 量子ビット\nlet 数 = 1"
        let tokens = highlighter.highlight(code, language: "swift")
        let text = code as NSString

        #expect(tokens.contains { text.substring(with: $0.range) == "let" && $0.kind == .keyword })
    }
}
