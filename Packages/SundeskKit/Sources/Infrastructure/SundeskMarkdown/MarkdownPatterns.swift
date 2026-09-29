//
//  MarkdownPatterns.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// CommonMark にない記法（数式、`[[リンク]]`、`#タグ`）を見つける。
/// コードの中にあるものは、呼び出す側で先に伏せておく。
enum MarkdownPatterns {
    // 固定の正規表現なので、失敗しない
    // swiftlint:disable force_try
    static let displayMath = try! NSRegularExpression(pattern: #"\$\$([\s\S]+?)\$\$"#)
    static let inlineMath = try! NSRegularExpression(pattern: #"\$([^$\n]+?)\$"#)
    static let wikilink = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+?)\]\]"#)
    // `#` の直前が文字や数字なら（URL の `#` や色の指定など）タグにしない
    static let tag = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_/&#])#([\p{L}\p{N}_/\-]*[\p{L}_/\-][\p{L}\p{N}_/\-]*)"#
    )
    // swiftlint:enable force_try

    struct Math {
        let range: NSRange
        let latex: String
        let isDisplay: Bool
    }

    /// 数式の範囲。`$ 5 と $ 10` のように、内側の両端が空白なら数式ではない。
    static func math(in text: String) -> [Math] {
        let string = text as NSString
        var found: [Math] = []
        for match in displayMath.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            found.append(Math(range: match.range, latex: string.substring(with: match.range(at: 1)), isDisplay: true))
        }
        let masked = mask(text, ranges: found.map(\.range)) as NSString
        for match in inlineMath.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)) {
            let inner = string.substring(with: match.range(at: 1))
            guard inner.first?.isWhitespace == false, inner.last?.isWhitespace == false else { continue }
            found.append(Math(range: match.range, latex: inner, isDisplay: false))
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    struct Wikilink {
        let range: NSRange
        /// リンク先（`#見出し` と表示名を除いたもの）。
        let target: String
        /// 表示名。なければリンク先の全体。
        let label: String
        /// 表示される部分（`|` の後ろ、なければ `[[` と `]]` の内側）の範囲。
        let labelRange: NSRange
    }

    static func wikilinks(in text: String) -> [Wikilink] {
        let string = text as NSString
        return wikilink.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let inner = match.range(at: 1)
            let separator = string.range(of: "|", range: inner)
            let labelRange =
                separator.location == NSNotFound
                ? inner
                : NSRange(location: NSMaxRange(separator), length: NSMaxRange(inner) - NSMaxRange(separator))
            return parseWikilink(string.substring(with: inner)).map {
                Wikilink(range: match.range, target: $0.target, label: $0.label, labelRange: labelRange)
            }
        }
    }

    /// `リンク先|表示名` を分ける。表の中で使う `\|` も区切りとして扱う。
    static func parseWikilink(_ inner: String) -> (target: String, label: String)? {
        let parts = inner.split(separator: /\\?\|/, maxSplits: 1)
        var target = (parts.first.map(String.init) ?? inner).trimmingCharacters(in: .whitespaces)
        while target.hasSuffix("\\") { target.removeLast() }
        let label = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : target
        var bare = target
        if let hash = bare.firstIndex(of: "#") { bare = String(bare[..<hash]) }
        bare = bare.trimmingCharacters(in: .whitespaces)
        guard !bare.isEmpty else { return nil }
        return (bare, label.isEmpty ? target : label)
    }

    static func tags(in text: String) -> [(range: NSRange, name: String)] {
        let string = text as NSString
        return tag.matches(in: text, range: NSRange(location: 0, length: string.length)).map {
            ($0.range, string.substring(with: $0.range(at: 1)))
        }
    }

    /// 範囲の中の文字を空白に置き換える（改行は残し、行の数と位置を変えない）。
    static func mask(_ text: String, ranges: [NSRange]) -> String {
        guard !ranges.isEmpty else { return text }
        var units = Array(text.utf16)
        for range in ranges {
            for index in range.location..<min(range.location + range.length, units.count) where units[index] != 0x0A {
                units[index] = 0x20
            }
        }
        return String(decoding: units, as: UTF16.self)
    }
}
