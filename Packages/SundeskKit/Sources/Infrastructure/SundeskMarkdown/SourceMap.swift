//
//  SourceMap.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Markdown

/// swift-markdown の位置（行と、行頭からの UTF-8 のバイト数）を、NSRange（UTF-16）に直す。
///
/// NSTextView や NSString は UTF-16 で位置を数えるので、日本語を含むノートでは変換が要る。
struct SourceMap {
    /// UTF-8 のバイト位置 → UTF-16 の位置（末尾を含む）。
    private let utf16ByUTF8: [Int]
    /// 各行の先頭の UTF-8 のバイト位置。
    private let lineStarts: [Int]
    /// この文字列が、文書全体のどこから始まるか（UTF-16）。フロントマターを除いた本文を解析するときに使う。
    let base: Int

    init(_ text: String, base: Int = 0) {
        var utf16ByUTF8: [Int] = []
        utf16ByUTF8.reserveCapacity(text.utf8.count + 1)
        var lineStarts = [0]
        var utf16 = 0
        for scalar in text.unicodeScalars {
            let utf8Length = String(scalar).utf8.count
            for _ in 0..<utf8Length { utf16ByUTF8.append(utf16) }
            utf16 += scalar.utf16.count
            if scalar == "\n" { lineStarts.append(utf16ByUTF8.count) }
        }
        utf16ByUTF8.append(utf16)
        self.utf16ByUTF8 = utf16ByUTF8
        self.lineStarts = lineStarts
        self.base = base
    }

    func offset(_ location: SourceLocation) -> Int? {
        guard location.line >= 1, location.line <= lineStarts.count else { return nil }
        let utf8 = lineStarts[location.line - 1] + location.column - 1
        guard utf8 >= 0, utf8 < utf16ByUTF8.count else { return nil }
        return base + utf16ByUTF8[utf8]
    }

    func range(_ range: SourceRange?) -> NSRange? {
        guard let range, let lower = offset(range.lowerBound), let upper = offset(range.upperBound), upper >= lower
        else {
            return nil
        }
        return NSRange(location: lower, length: upper - lower)
    }
}
