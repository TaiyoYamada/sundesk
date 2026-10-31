//
//  PaperTitle.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// PDF から拾った題名の候補を見分け、検索で返ってきた書誌情報と突き合わせる。
public enum PaperTitle {
    /// 題名としてありうる文字列か。PDF に埋め込まれた題名は、元の文書のファイル名（「Microsoft Word - tr062.doc」）や、
    /// 文字の対応が壊れた記号の列（「( %)*++ , - ./」）のことがあるので除く。
    public static func isPlausible(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...300).contains(trimmed.count) else { return false }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("microsoft word") || lowered.hasPrefix("untitled") { return false }
        if trimmed.contains(":/") || trimmed.contains("\\") { return false }
        if lowered.wholeMatch(of: /.*\.(docx?|dvi|tiff?|indd|qxp|key|pdf|tex|ps)/) != nil { return false }
        // 雑誌の欄外（「Vol. 47 No. SIG 14」「VOL. 13, NO. 2」）
        if lowered.firstMatch(of: /\bvol\.?\s*\d+.*\bno\.?\s*\S/) != nil { return false }
        let visible = trimmed.filter { !$0.isWhitespace }
        let letters = visible.filter(\.isLetter)
        return Double(letters.count) >= Double(visible.count) * 0.6
    }

    /// PDF から拾った題名と、検索で返ってきた書誌情報の題名が同じ論文のものか。
    /// 片方が副題を落としていたり、PDF の文字のまとまりが題名の後ろに著者名まで含んでいたりするので、
    /// 短いほうが長いほうの先頭と一致すれば同じとみなす。ただし短い題名（「Preliminary」「Differential Evolution」）は
    /// 別の論文の先頭とも一致しやすいので、先頭の一致は 30 文字以上のときだけにする。
    public static func matches(_ candidate: ReferenceMetadata, title: String) -> Bool {
        let found = normalize(candidate.title)
        let wanted = normalize(title)
        guard found.count >= 15, wanted.count >= 15 else { return false }
        let (shorter, longer) = found.count < wanted.count ? (found, wanted) : (wanted, found)
        if shorter.count >= 30, longer.hasPrefix(shorter) { return true }
        return similarity(found, wanted) >= 0.85
    }

    /// 書誌情報が、ファイル名の年と著者に食い違うか。ファイル名に年がないときは、食い違うとは言えないので false。
    /// PDF の中の DOI は、参考文献に挙げた別の論文のものを拾うことがあるので、これで確かめる。
    /// Crossref の著者のデータは壊れていることがあるので、題名の語が 2 つ以上合えば、著者は見ない。
    public static func contradicts(_ candidate: ReferenceMetadata, hint: FileNameHint) -> Bool {
        guard let year = hint.year else { return false }
        if let found = candidate.issued?.year, abs(found - year) > 1 { return true }
        let words = hint.words.map(normalize).filter { !$0.isEmpty }
        if matchedTitleWords(candidate, words: words).count >= 2 { return false }
        switch authorAgreement(candidate, words: words) {
        case .agrees, .unknown: return false
        case .disagrees, .missing: return true
        }
    }

    /// ファイル名の手がかりと、検索で返ってきた書誌情報が合うか。ファイル名の語は略されているので、
    /// 年（1 年のずれまで）、著者の姓、題名の語の 2 つ以上が合うことを求める。
    public static func matches(_ candidate: ReferenceMetadata, hint: FileNameHint) -> Bool {
        if let year = hint.year, let found = candidate.issued?.year, abs(found - year) > 1 { return false }
        let words = hint.words.map(normalize).filter { !$0.isEmpty }
        switch authorAgreement(candidate, words: words) {
        case .agrees, .unknown: break
        // 著者のない結果（事典の項目など）は、題名の語が合っても取り違えやすい
        case .disagrees, .missing: return false
        }
        let matched = matchedTitleWords(candidate, words: words)
        return matched.count >= 2 || (matched.count == 1 && !matched[0].allSatisfy(\.isASCII))
    }

    private enum AuthorAgreement {
        case agrees
        case disagrees
        /// 著者がいない。
        case missing
        /// 著者の姓がどれもローマ字でないので、ローマ字のファイル名とは比べられない。
        case unknown
    }

    /// 著者のだれかの姓がファイル名にあるか。筆頭が団体名（「University of Latvia」）のこともあるので、全員を見る。
    private static func authorAgreement(_ candidate: ReferenceMetadata, words: [String]) -> AuthorAgreement {
        let families = candidate.authors.map { normalize($0.family) }.filter { !$0.isEmpty }
        guard !families.isEmpty else { return .missing }
        let ascii = families.filter { $0.allSatisfy(\.isASCII) }
        guard !ascii.isEmpty else { return .unknown }
        // 「Juska」と「Juska-Mirbaha」のように、片方がもう片方を含んでいればよい
        let agrees = ascii.contains { family in
            words.contains { $0.contains(family) || ($0.count >= 3 && family.contains($0)) }
        }
        return agrees ? .agrees : .disagrees
    }

    /// ファイル名の語のうち、題名に出てくるもの（ローマ字は 4 文字以上。日本語は似ていればよい）。
    private static func matchedTitleWords(_ candidate: ReferenceMetadata, words: [String]) -> [String] {
        let title = normalize(candidate.title)
        return words.filter { word in
            if word.allSatisfy(\.isASCII) { return word.count >= 4 && title.contains(word) }
            return similarity(word, title) >= 0.4 || title.contains(word)
        }
    }

    /// 小文字にし、アクセントを外し、文字と数字だけを残す。
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// 2 文字ずつの組の重なり（Dice 係数）。語の区切りのない日本語にも使える。
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        func bigrams(_ text: String) -> [String: Int] {
            let characters = Array(text)
            guard characters.count > 1 else { return [text: 1] }
            var counts: [String: Int] = [:]
            for index in 0..<(characters.count - 1) {
                counts[String(characters[index...index + 1]), default: 0] += 1
            }
            return counts
        }
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        let common = left.reduce(0) { $0 + min($1.value, right[$1.key] ?? 0) }
        let total = left.values.reduce(0, +) + right.values.reduce(0, +)
        return total == 0 ? 0 : 2 * Double(common) / Double(total)
    }
}
