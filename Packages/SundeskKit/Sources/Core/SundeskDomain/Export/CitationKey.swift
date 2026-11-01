//
//  CitationKey.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// BibTeX の引用キーを作る。形は Google Scholar と同じ「姓 + 年 + 題名の最初の語」（例: peruzzo2014variational）。
/// 日本語の姓と題名は、読みのローマ字にする（例: 福山「ゲーミフィケーションの…」2017 → fukuyama2017gemifikeshon）。
public enum CitationKey {
    /// 題名の最初の語として数えない語。
    private static let skippedWords: Set<String> = [
        "a", "an", "the", "on", "of", "in", "for", "to", "and", "with", "via", "from", "at", "by",
    ]

    /// - Parameter existing: すでに使っているキー。重なるときは末尾に a、b、c… を付ける。
    public static func make(for metadata: ReferenceMetadata, existing: Set<String>) -> String {
        let family = metadata.authors.first.map { words($0.family).joined() } ?? ""
        let year = metadata.issued.map { String($0.year) } ?? ""
        // 数字だけの語（ファイル名を題名にした「2005_Ronkkonen」の年など）は、年と並んで読めなくなるので飛ばす
        let word = words(metadata.title).first { !skippedWords.contains($0) && !$0.allSatisfy(\.isNumber) } ?? ""
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

    /// 語に分け、それぞれを小文字の英数字にする。日本語の語は、読みのローマ字にする（点字学習 → tenji、gakushuu）。
    private static func words(_ text: String) -> [String] {
        let string = text as NSString
        // 日本語の辞書で区切ると、英語の語も空白と記号で区切られる
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: string.length), kCFStringTokenizerUnitWord,
            Locale(identifier: "ja") as CFLocale)
        var words: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = string.substring(with: NSRange(location: range.location, length: range.length))
            let reading =
                CFStringTokenizerCopyCurrentTokenAttribute(
                    tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            // 英字の語まで読みにすると、ICT が aishiti になる
            words.append(ascii(Creator.isCJK(token) ? reading ?? "" : token))
        }
        return words.filter { !$0.isEmpty }
    }

    /// アクセントを外し、小文字の英数字だけを残す。
    private static func ascii(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
