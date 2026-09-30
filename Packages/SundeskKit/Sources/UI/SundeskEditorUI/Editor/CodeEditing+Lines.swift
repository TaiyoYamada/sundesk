//
//  CodeEditing+Lines.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

extension CodeEditing {
    // MARK: - 行の扱い

    /// 1 行の書き換え。行頭から `column` の位置で `delete` 文字消して `insert` を入れる。
    struct LineChange {
        var column: Int
        var delete: Int
        var insert: String
    }

    /// 本文の 1 行。
    struct Line {
        /// 行頭の位置。
        let start: Int
        /// 改行を除いた中身。
        let text: String
        /// 行末の改行（最後の行なら空）。
        let newline: String
    }

    /// 選択範囲にかかる行を 1 行ずつ書き換え、1 回の書き換えにまとめる。選択範囲は書き換えに合わせて動かす。
    func changeLines(_ string: NSString, _ selection: NSRange, _ change: (String) -> LineChange?) -> CodeEdit {
        let block = Self.lineBlock(string, selection)
        // 本文の中の位置に直した書き換え
        var changes: [LineChange] = []
        var replacement = ""
        for line in Self.lines(in: string, block) {
            if let lineChange = change(line.text) {
                let text = line.text as NSString
                let column = min(lineChange.column, text.length)
                let delete = min(lineChange.delete, text.length - column)
                replacement +=
                    text.substring(to: column) + lineChange.insert + text.substring(from: column + delete)
                changes.append(LineChange(column: line.start + column, delete: delete, insert: lineChange.insert))
            } else {
                replacement += line.text
            }
            replacement += line.newline
        }
        func map(_ position: Int, keepsBefore: Bool) -> Int {
            var delta = 0
            for change in changes {
                if position < change.column || (position == change.column && keepsBefore) { break }
                if position <= change.column + change.delete {
                    return change.column + delta + change.insert.utf16.count
                }
                delta += change.insert.utf16.count - change.delete
            }
            return position + delta
        }
        let isCaret = selection.length == 0
        let start = map(selection.location, keepsBefore: !isCaret)
        let end = isCaret ? start : map(NSMaxRange(selection), keepsBefore: false)
        return CodeEdit(
            range: block, replacement: replacement, selection: NSRange(location: start, length: end - start))
    }

    /// 選択範囲にかかる行の範囲（最後の改行を含む）。次の行の頭で終わる選択は、その行を含めない。
    static func lineBlock(_ string: NSString, _ selection: NSRange) -> NSRange {
        var end = NSMaxRange(selection)
        if selection.length > 0, character(in: string, at: end - 1) == "\n" { end -= 1 }
        return string.lineRange(for: NSRange(location: selection.location, length: end - selection.location))
    }

    static func lines(in string: NSString, _ block: NSRange) -> [Line] {
        var result: [Line] = []
        var location = block.location
        repeat {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            let end = contentEnd(of: string, lineStart: line.location)
            result.append(
                Line(
                    start: line.location,
                    text: string.substring(with: NSRange(location: line.location, length: end - line.location)),
                    newline: string.substring(with: NSRange(location: end, length: NSMaxRange(line) - end))))
            location = NSMaxRange(line)
        } while location < NSMaxRange(block)
        return result
    }

    /// 行の、改行を除いた終わり。
    static func contentEnd(of string: NSString, lineStart: Int) -> Int {
        var start = 0
        var end = 0
        var contentsEnd = 0
        string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
        return contentsEnd
    }

    /// 選択範囲が複数の行にかかるか。
    static func spansLines(_ string: NSString, _ selection: NSRange) -> Bool {
        selection.length > 0 && string.substring(with: selection).contains("\n")
    }

    static func character(in string: NSString, at location: Int) -> Character? {
        guard location >= 0, location < string.length,
            let scalar = Unicode.Scalar(string.character(at: location))
        else { return nil }
        return Character(scalar)
    }

    static func isIdentifier(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}

extension String {
    /// 末尾の空白を除いた文字列。
    var trimmingTrailingWhitespace: String {
        var result = self
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }
}
