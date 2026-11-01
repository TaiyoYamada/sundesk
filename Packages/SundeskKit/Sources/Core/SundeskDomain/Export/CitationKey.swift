//
//  CitationKey.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// BibTeX の引用キーを作る。形は Google Scholar と同じ「姓 + 年 + 題名の最初の語」（例: peruzzo2014variational）。
public enum CitationKey {
    /// 題名の最初の語として数えない語。
    private static let skippedWords: Set<String> = [
        "a", "an", "the", "on", "of", "in", "for", "to", "and", "with", "via", "from", "at", "by",
    ]

    /// - Parameter existing: すでに使っているキー。重なるときは末尾に a、b、c… を付ける。
    public static func make(for metadata: ReferenceMetadata, existing: Set<String>) -> String {
        let family = metadata.authors.first.map { ascii($0.family) } ?? ""
        let year = metadata.issued.map { String($0.year) } ?? ""
        let word =
            metadata.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { ascii(String($0)) }
            .first { !$0.isEmpty && !skippedWords.contains($0) } ?? ""
        var base = family + year + word
        if base.isEmpty { base = "ref" }

        guard existing.contains(base) else { return base }
        for suffix in "abcdefghijklmnopqrstuvwxyz" where !existing.contains(base + String(suffix)) {
            return base + String(suffix)
        }
        var number = 2
        while existing.contains(base + String(number)) { number += 1 }
        return base + String(number)
    }

    /// アクセントを外し、小文字の英数字だけを残す（漢字や仮名は残らない）。
    private static func ascii(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
