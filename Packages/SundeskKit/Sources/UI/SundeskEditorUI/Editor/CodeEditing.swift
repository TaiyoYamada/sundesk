//
//  CodeEditing.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// コードの編集で、本文のどこをどう書き換えるか。
struct CodeEdit: Equatable {
    /// 書き換える範囲（UTF-16）。
    var range: NSRange
    var replacement: String
    /// 書き換えたあとの選択範囲。
    var selection: NSRange

    /// 文字は変えず、カーソルだけ動かすか。
    var movesOnly: Bool { range.length == 0 && replacement.isEmpty }
}

/// コードのエディタの操作（キーボードのショートカットと同じ）。
public enum CodeCommand: Sendable, CaseIterable {
    /// 行コメントの切り替え（⌘/）。
    case toggleComment
    /// 行の複製（⌘D）。
    case duplicateLines
    /// 行を上へ（⌥↑）。
    case moveLinesUp
    /// 行を下へ（⌥↓）。
    case moveLinesDown
    /// インデントを増やす（⌘]）。
    case indent
    /// インデントを減らす（⌘[）。
    case dedent
}

/// コードを書くときの編集（自動インデント、インデントの増減、コメント、行の複製と移動、括弧とクォートの補完）。
///
/// 本文と選択範囲から書き換えを計算するだけで、NSTextView には触らない（テストしやすくするため）。
/// 位置と範囲は、NSTextView と同じく UTF-16 で数える。
struct CodeEditing: Equatable {
    let language: String

    init(language: String) {
        self.language = language.lowercased()
    }

    // MARK: - 言語ごとの決まり

    /// 1 段のインデント。
    var indentUnit: String {
        ["yaml", "json", "html", "css", "javascript", "typescript", "tsx"].contains(language) ? "  " : "    "
    }

    /// 行コメントの記号。ない言語は nil。
    var lineComment: String? {
        switch language {
        case "python", "bash", "sh", "shell", "zsh", "yaml", "toml", "ruby", "r": "#"
        case "swift", "javascript", "typescript", "tsx", "c", "cpp", "java", "go", "rust", "kotlin": "//"
        default: nil
        }
    }

    /// 行末の `:` でブロックが始まる言語か。
    var usesColonBlocks: Bool { language == "python" }

    /// 対にして補うクォート。
    var quotes: Set<Character> {
        switch language {
        case "swift", "rust", "c", "cpp", "java", "go", "kotlin": ["\""]
        default: ["\"", "'"]
        }
    }

    static let brackets: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    static let closers: Set<Character> = [")", "]", "}"]

    // MARK: - 改行

    /// 改行して、前の行のインデントを引き継ぐ。ブロックの始まり（`:` や開き括弧）の後は 1 段深くする。
    func newline(in text: String, selection: NSRange) -> CodeEdit {
        let string = text as NSString
        let lineStart = string.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let before = string.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let indent = String(before.prefix { $0 == " " || $0 == "\t" })
        let code = codePart(of: before).trimmingTrailingWhitespace

        // 空白だけの行で改行したら、その空白は残さない
        let lineEnd = Self.contentEnd(of: string, lineStart: lineStart)
        let rest = string.substring(
            with: NSRange(location: NSMaxRange(selection), length: max(lineEnd - NSMaxRange(selection), 0)))
        if !before.isEmpty, code.isEmpty, rest.allSatisfy(\.isWhitespace) {
            let range = NSRange(location: lineStart, length: NSMaxRange(selection) - lineStart)
            let replacement = "\n" + indent
            return CodeEdit(
                range: range, replacement: replacement,
                selection: NSRange(location: lineStart + replacement.utf16.count, length: 0))
        }

        var newIndent = indent
        if opensBlock(code) {
            newIndent += indentUnit
        } else if closesBlock(code) {
            newIndent = dedented(indent)
        }
        // 括弧の間での改行は、閉じ括弧を次の行に送る
        if let last = code.last, let closer = Self.brackets[last],
            Self.character(in: string, at: NSMaxRange(selection)) == closer
        {
            let first = "\n" + newIndent
            return CodeEdit(
                range: selection, replacement: first + "\n" + indent,
                selection: NSRange(location: selection.location + first.utf16.count, length: 0))
        }
        let replacement = "\n" + newIndent
        return CodeEdit(
            range: selection, replacement: replacement,
            selection: NSRange(location: selection.location + replacement.utf16.count, length: 0))
    }

    private func opensBlock(_ code: String) -> Bool {
        guard let last = code.last else { return false }
        return Self.brackets[last] != nil || (usesColonBlocks && last == ":")
    }

    /// これで終わるとブロックを抜ける行か（Python の return や pass）。
    private func closesBlock(_ code: String) -> Bool {
        guard usesColonBlocks else { return false }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        return trimmed.wholeMatch(of: /(return|pass|break|continue|raise)(\s.*)?/) != nil
    }

    private func dedented(_ indent: String) -> String {
        if indent.hasSuffix("\t") { return String(indent.dropLast()) }
        let spaces = indent.reversed().prefix { $0 == " " }.count
        return String(indent.dropLast(min(spaces, indentUnit.count)))
    }

    /// 行のうち、コメントを除いたコードの部分（文字列の中の記号は数えない）。
    private func codePart(of line: String) -> String {
        guard let comment = lineComment else { return line }
        var quote: Character?
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if line[index...].hasPrefix(comment) {
                return String(line[..<index])
            }
            index = line.index(after: index)
        }
        return line
    }

    // MARK: - インデント

    /// Tab。複数の行を選んでいればそれらを 1 段深くし、そうでなければ次のタブ位置まで空白を入れる。
    func indent(in text: String, selection: NSRange) -> CodeEdit {
        let string = text as NSString
        guard Self.spansLines(string, selection) else {
            let lineStart = string.lineRange(for: NSRange(location: selection.location, length: 0)).location
            let column = selection.location - lineStart
            let count = indentUnit.count - column % indentUnit.count
            return CodeEdit(
                range: selection, replacement: String(repeating: " ", count: count),
                selection: NSRange(location: selection.location + count, length: 0))
        }
        return indentLines(in: text, selection: selection)
    }

    /// 選んだ行（選んでいなければカーソルの行）を 1 段深くする。
    func indentLines(in text: String, selection: NSRange) -> CodeEdit {
        changeLines(text as NSString, selection) { line in
            line.allSatisfy(\.isWhitespace) ? nil : LineChange(column: 0, delete: 0, insert: indentUnit)
        }
    }

    /// Shift-Tab。選んだ行（選んでいなければカーソルの行）を 1 段浅くする。
    func dedent(in text: String, selection: NSRange) -> CodeEdit? {
        let string = text as NSString
        let edit = changeLines(string, selection) { line in
            if line.hasPrefix("\t") { return LineChange(column: 0, delete: 1, insert: "") }
            let spaces = min(line.prefix { $0 == " " }.count, indentUnit.count)
            return spaces > 0 ? LineChange(column: 0, delete: spaces, insert: "") : nil
        }
        return edit.replacement == string.substring(with: edit.range) ? nil : edit
    }

    // MARK: - コメント

    /// 選んだ行のコメントを切り替える。すべてコメントなら外し、そうでなければ揃えた位置に付ける。
    func toggleComment(in text: String, selection: NSRange) -> CodeEdit? {
        guard let comment = lineComment else { return nil }
        let string = text as NSString
        let lines = Self.lines(in: string, Self.lineBlock(string, selection))
        let filled = lines.filter { !$0.text.allSatisfy(\.isWhitespace) }
        let isCommented =
            !filled.isEmpty
            && filled.allSatisfy { $0.text.drop { $0 == " " || $0 == "\t" }.hasPrefix(comment) }
        if isCommented {
            return changeLines(string, selection) { line in
                let indent = line.prefix { $0 == " " || $0 == "\t" }.count
                let body = line.dropFirst(indent)
                guard body.hasPrefix(comment) else { return nil }
                let space = body.dropFirst(comment.count).first == " " ? 1 : 0
                return LineChange(column: indent, delete: comment.utf16.count + space, insert: "")
            }
        }
        let column = filled.map { $0.text.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let onlyBlank = filled.isEmpty
        return changeLines(string, selection) { line in
            guard onlyBlank || !line.allSatisfy(\.isWhitespace) else { return nil }
            return LineChange(column: min(column, line.utf16.count), delete: 0, insert: comment + " ")
        }
    }
}
