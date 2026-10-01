//
//  CodeEditing+Editing.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

extension CodeEditing {
    // MARK: - 行の複製と移動

    /// 選んだ行（選んでいなければカーソルの行）を、すぐ下に複製する。
    func duplicateLines(in text: String, selection: NSRange) -> CodeEdit {
        let string = text as NSString
        let block = Self.lineBlock(string, selection)
        let content = string.substring(with: block)
        let insertion = content.hasSuffix("\n") ? content : "\n" + content
        return CodeEdit(
            range: NSRange(location: NSMaxRange(block), length: 0), replacement: insertion,
            selection: NSRange(location: selection.location + insertion.utf16.count, length: selection.length))
    }

    /// 選んだ行を 1 行上か下へ動かす。端なら nil。
    func moveLines(upward: Bool, in text: String, selection: NSRange) -> CodeEdit? {
        let string = text as NSString
        let block = Self.lineBlock(string, selection)
        let range: NSRange
        if upward {
            guard block.location > 0 else { return nil }
            let previous = string.lineRange(for: NSRange(location: block.location - 1, length: 0))
            range = NSRange(location: previous.location, length: NSMaxRange(block) - previous.location)
        } else {
            guard NSMaxRange(block) < string.length else { return nil }
            let next = string.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            range = NSRange(location: block.location, length: NSMaxRange(next) - block.location)
        }
        let content = string.substring(with: range)
        let hasTrailingNewline = content.hasSuffix("\n")
        var lines = (hasTrailingNewline ? String(content.dropLast()) : content).components(separatedBy: "\n")
        let shift: Int
        if upward {
            let previous = lines.removeFirst()
            lines.append(previous)
            shift = -(previous.utf16.count + 1)
        } else {
            let next = lines.removeLast()
            lines.insert(next, at: 0)
            shift = next.utf16.count + 1
        }
        return CodeEdit(
            range: range, replacement: lines.joined(separator: "\n") + (hasTrailingNewline ? "\n" : ""),
            selection: NSRange(location: selection.location + shift, length: selection.length))
    }

    // MARK: - 括弧とクォート

    /// 1 文字を打ったとき。括弧やクォートを対にして補う、閉じ記号を飛び越す、選んだ文字を囲む。
    /// 何もしないときは nil（ふつうに入力する）。
    func insert(_ input: String, in text: String, selection: NSRange) -> CodeEdit? {
        guard input.count == 1, let character = input.first else { return nil }
        let string = text as NSString
        let next = Self.character(in: string, at: NSMaxRange(selection))
        let previous = Self.character(in: string, at: selection.location - 1)
        let isQuote = quotes.contains(character)

        // 補った閉じ記号は、上書きせずに飛び越す
        if selection.length == 0, next == character, Self.closers.contains(character) || isQuote {
            return CodeEdit(
                range: NSRange(location: selection.location, length: 0), replacement: "",
                selection: NSRange(location: selection.location + 1, length: 0))
        }
        guard let closer = Self.brackets[character] ?? (isQuote ? character : nil) else { return nil }
        if selection.length > 0 {
            let selected = string.substring(with: selection)
            return CodeEdit(
                range: selection, replacement: "\(character)\(selected)\(closer)",
                selection: NSRange(location: selection.location + 1, length: selection.length))
        }
        // 語の直前では補わない
        if let next, !(next.isWhitespace || ")]},:;".contains(next)) { return nil }
        if isQuote, let previous {
            // 語の途中（don't など）や、3 つめのクォート（"""）では補わない
            if previous == character { return nil }
            if Self.isIdentifier(previous), !isStringPrefix(in: string, before: selection.location) { return nil }
        }
        return CodeEdit(
            range: selection, replacement: "\(character)\(closer)",
            selection: NSRange(location: selection.location + 1, length: 0))
    }

    /// Python の f"…" や r"…" の接頭辞か。
    private func isStringPrefix(in string: NSString, before location: Int) -> Bool {
        guard usesColonBlocks, let previous = Self.character(in: string, at: location - 1),
            "fFrRbBuU".contains(previous)
        else { return false }
        guard let beforePrefix = Self.character(in: string, at: location - 2) else { return true }
        return !Self.isIdentifier(beforePrefix)
    }

    /// ⌫。空の対（`()` や `""`）は両方消し、行頭の空白の中ではインデント 1 段ぶん消す。
    /// ふつうに消すときは nil。
    func deleteBackward(in text: String, selection: NSRange) -> CodeEdit? {
        guard selection.length == 0, selection.location > 0 else { return nil }
        let string = text as NSString
        let location = selection.location
        if let previous = Self.character(in: string, at: location - 1),
            let next = Self.character(in: string, at: location),
            Self.brackets[previous] == next || (quotes.contains(previous) && previous == next)
        {
            return CodeEdit(
                range: NSRange(location: location - 1, length: 2), replacement: "",
                selection: NSRange(location: location - 1, length: 0))
        }
        let lineStart = string.lineRange(for: NSRange(location: location, length: 0)).location
        let before = string.substring(with: NSRange(location: lineStart, length: location - lineStart))
        guard before.count > 1, before.allSatisfy({ $0 == " " }) else { return nil }
        let count = (before.count - 1) % indentUnit.count + 1
        return CodeEdit(
            range: NSRange(location: location - count, length: count), replacement: "",
            selection: NSRange(location: location - count, length: 0))
    }

    // MARK: - 実行する部分

    /// 選んだ文字（選んでいなければカーソルの行）。共通のインデントは除く（ブロックの中の行だけでも動かせるように）。
    static func selectedCode(in text: String, selection: NSRange) -> String {
        let string = text as NSString
        guard selection.length == 0 else { return removingCommonIndent(string.substring(with: selection)) }
        let lineStart = string.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let end = contentEnd(of: string, lineStart: lineStart)
        return removingCommonIndent(string.substring(with: NSRange(location: lineStart, length: end - lineStart)))
    }

    /// 空でない行に共通する行頭の空白を除く（Python の textwrap.dedent と同じ）。
    static func removingCommonIndent(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        let indents = lines.filter { !$0.allSatisfy(\.isWhitespace) }.map {
            $0.prefix { $0 == " " || $0 == "\t" }.count
        }
        guard let common = indents.min(), common > 0 else { return code }
        return lines.map { $0.allSatisfy(\.isWhitespace) ? "" : String($0.dropFirst(common)) }.joined(separator: "\n")
    }
}
