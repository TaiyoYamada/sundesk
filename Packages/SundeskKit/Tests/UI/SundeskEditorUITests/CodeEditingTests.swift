//
//  CodeEditingTests.swift
//  SundeskEditorUITests
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import Foundation
import Testing

@testable import SundeskEditorUI

/// 「‸」をカーソル、「«…»」を選択範囲として書いた本文を、本文と選択範囲に分ける。
private func parse(_ marked: String) -> (text: String, selection: NSRange) {
    var text = marked as NSString
    let caret = text.range(of: "‸")
    if caret.location != NSNotFound {
        text = text.replacingCharacters(in: caret, with: "") as NSString
        return (text as String, NSRange(location: caret.location, length: 0))
    }
    let start = text.range(of: "«").location
    text = text.replacingCharacters(in: NSRange(location: start, length: 1), with: "") as NSString
    let end = text.range(of: "»").location
    text = text.replacingCharacters(in: NSRange(location: end, length: 1), with: "") as NSString
    return (text as String, NSRange(location: start, length: end - start))
}

/// 書き換えを当てた結果を、同じ書き方で返す。
private func render(_ edit: CodeEdit?, _ text: String) -> String? {
    guard let edit else { return nil }
    let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
    if edit.selection.length == 0 {
        return result.replacingCharacters(in: edit.selection, with: "‸")
    }
    let closed = result.replacingCharacters(in: NSRange(location: NSMaxRange(edit.selection), length: 0), with: "»")
    return (closed as NSString).replacingCharacters(
        in: NSRange(location: edit.selection.location, length: 0), with: "«")
}

private let python = CodeEditing(language: "python")

/// 1 文字打ったときの例（打つ前の本文、打つ文字、打ったあとの本文）。
nonisolated struct Typing: Sendable, CustomTestStringConvertible {
    let marked: String
    let input: String
    let expected: String?

    init(_ marked: String, _ input: String, _ expected: String?) {
        self.marked = marked
        self.input = input
        self.expected = expected
    }

    var testDescription: String { "\(marked) に \(input)" }
}

private func run(_ marked: String, _ body: (String, NSRange) -> CodeEdit?) -> String? {
    let (text, selection) = parse(marked)
    return render(body(text, selection), text)
}

@Suite("CodeEditing")
struct CodeEditingTests {
    // MARK: - 改行

    @Test(
        "改行で前の行のインデントを引き継ぎ、: の後は 1 段深くする",
        arguments: [
            ("    x = 1‸", "    x = 1\n    ‸"),
            ("for i in range(3):‸", "for i in range(3):\n    ‸"),
            ("    if a:  # コメント‸", "    if a:  # コメント\n        ‸"),
            ("        return x‸", "        return x\n    ‸"),
            ("print(‸)", "print(\n    ‸\n)"),
            ("    ‸", "\n    ‸"),
            ("s = \"a:\"‸", "s = \"a:\"\n‸"),
        ])
    func newline(marked: String, expected: String) {
        #expect(run(marked) { python.newline(in: $0, selection: $1) } == expected)
    }

    // MARK: - インデント

    @Test("Tab は次のタブ位置まで空白を入れ、複数行を選んでいれば行ごと深くする")
    func indent() {
        #expect(run("ab‸") { python.indent(in: $0, selection: $1) } == "ab  ‸")
        #expect(
            run("«a\n\nb»\nc") { python.indent(in: $0, selection: $1) } == "«    a\n\n    b»\nc")
        #expect(
            run("x = «1\ny» = 2") { python.indent(in: $0, selection: $1) } == "    x = «1\n    y» = 2")
    }

    @Test("Shift-Tab は選んだ行か、カーソルの行を 1 段浅くする")
    func dedent() {
        #expect(run("        x‸ = 1") { python.dedent(in: $0, selection: $1) } == "    x‸ = 1")
        #expect(run("«    a\n  b\nc»") { python.dedent(in: $0, selection: $1) } == "«a\nb\nc»")
        #expect(run("x‸") { python.dedent(in: $0, selection: $1) } == nil)
    }

    // MARK: - コメント

    @Test("⌘/ で揃えた位置にコメントを付け、すべてコメントなら外す")
    func toggleComment() {
        #expect(
            run("«    a = 1\n\n        b = 2»") { python.toggleComment(in: $0, selection: $1) }
                == "«    # a = 1\n\n    #     b = 2»")
        #expect(run("    # a‸ = 1") { python.toggleComment(in: $0, selection: $1) } == "    a‸ = 1")
        #expect(run("x‸") { CodeEditing(language: "swift").toggleComment(in: $0, selection: $1) } == "// x‸")
        #expect(run("x‸") { CodeEditing(language: "markdown").toggleComment(in: $0, selection: $1) } == nil)
    }

    // MARK: - 行の複製と移動

    @Test("⌘D でカーソルの行を下に複製する")
    func duplicate() {
        #expect(run("a\nb‸c\nd") { python.duplicateLines(in: $0, selection: $1) } == "a\nbc\nb‸c\nd")
        #expect(run("a\nb‸") { python.duplicateLines(in: $0, selection: $1) } == "a\nb\nb‸")
        #expect(run("«a\nb\n»c") { python.duplicateLines(in: $0, selection: $1) } == "a\nb\n«a\nb\n»c")
    }

    @Test("⌥↑↓ で行を動かす。端では何もしない")
    func move() {
        #expect(run("a\nb‸\nc") { python.moveLines(upward: true, in: $0, selection: $1) } == "b‸\na\nc")
        #expect(run("a\nb‸\nc") { python.moveLines(upward: false, in: $0, selection: $1) } == "a\nc\nb‸")
        #expect(run("«a\nb»\nc") { python.moveLines(upward: false, in: $0, selection: $1) } == "c\n«a\nb»")
        #expect(run("a‸\nb") { python.moveLines(upward: true, in: $0, selection: $1) } == nil)
        #expect(run("a\nb‸") { python.moveLines(upward: false, in: $0, selection: $1) } == nil)
    }

    // MARK: - 括弧とクォート

    @Test(
        "括弧とクォートを対にし、閉じ記号は飛び越し、選んだ文字は囲む",
        arguments: [
            Typing("x = ‸", "(", "x = (‸)"),
            Typing("f(‸)", ")", "f()‸"),
            Typing("‸", "\"", "\"‸\""),
            Typing("\"‸\"", "\"", "\"\"‸"),
            Typing("x = f‸", "\"", "x = f\"‸\""),
            Typing("don‸", "'", nil),
            Typing("‸abc", "(", nil),
            Typing("«abc»", "[", "[«abc»]"),
            Typing("a‸", "x", nil),
        ])
    func pairs(typing: Typing) {
        #expect(run(typing.marked) { python.insert(typing.input, in: $0, selection: $1) } == typing.expected)
    }

    @Test("⌫ で空の対を両方消し、行頭の空白ではインデント 1 段ぶん消す")
    func deleteBackward() {
        #expect(run("f(‸)") { python.deleteBackward(in: $0, selection: $1) } == "f‸")
        #expect(run("      ‸x") { python.deleteBackward(in: $0, selection: $1) } == "    ‸x")
        #expect(run("a ‸") { python.deleteBackward(in: $0, selection: $1) } == nil)
    }

    // MARK: - 実行する部分

    @Test("選んだ部分かカーソルの行を、共通のインデントを除いて取り出す")
    func selectedCode() {
        let (text, caret) = parse("for i in x:\n    print(‸i)\n")
        #expect(CodeEditing.selectedCode(in: text, selection: caret) == "print(i)")
        let (block, selection) = parse("if a:\n«    b = 1\n        c = 2»\n")
        #expect(CodeEditing.selectedCode(in: block, selection: selection) == "b = 1\n    c = 2")
    }
}

@Suite("CodeCompletion")
struct CodeCompletionTests {
    @Test("本文の識別子と足した名前を先に、キーワードと組み込みを後に出す")
    func candidates() {
        let text = "prompt_tokens = tokenizer.encode(prompt)\nshow(prompt_tokens)"
        let result = CodeCompletion.candidates(prefix: "pr", text: text, language: "python", extra: ["plt"])
        #expect(result.prefix(2) == ["prompt", "prompt_tokens"])
        #expect(result.contains("print"))
        #expect(result.contains("property"))
        #expect(!result.contains("plt"))
        #expect(CodeCompletion.candidates(prefix: "pl", text: "", language: "python", extra: ["plt"]) == ["plt"])
    }
}

@MainActor
@Suite("EditorTextView のコードの編集")
struct EditorTextViewCodeTests {
    @Test("Python では改行で自動インデントし、括弧を補い、⌘/ でコメントを切り替える")
    func editsPython() throws {
        let session = TextEditorSession()
        var received = ""
        session.onTextChange = { received = $0 }
        session.update(text: "if a:", syntax: .code(language: "python"))
        session.textView.setSelectedRange(NSRange(location: 5, length: 0))

        session.textView.insertNewline(nil)
        #expect(session.string == "if a:\n    ")
        #expect(received == "if a:\n    ")

        session.textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(session.string == "if a:\n    ()")

        session.perform(.toggleComment)
        #expect(session.string == "if a:\n    # ()")
        #expect(session.textView.highlightsCurrentLine)
    }

    @Test("Markdown では自動インデントも括弧の補完もしない")
    func leavesMarkdownAlone() {
        let session = TextEditorSession()
        session.update(text: "- a:", syntax: .markdown(livePreview: false, notePath: "a.md"))
        session.textView.setSelectedRange(NSRange(location: 4, length: 0))

        session.textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
        session.textView.insertNewline(nil)

        #expect(session.string == "- a:(\n")
        #expect(session.textView.codeEditing == nil)
        #expect(!session.textView.highlightsCurrentLine)
    }

    @Test("選んでいなければ、カーソルの行を実行する部分として返す")
    func selectedTextOrCurrentLine() {
        let session = TextEditorSession()
        session.update(text: "a = 1\n    b = 2", syntax: .code(language: "python"))
        session.textView.setSelectedRange(NSRange(location: 8, length: 0))

        #expect(session.selectedTextOrCurrentLine == "b = 2")
    }
}
