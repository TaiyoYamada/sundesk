import Foundation
import NaturalLanguage

nonisolated struct SearchHit: Identifiable, Hashable, Sendable {
    var id: String { noteID }
    let noteID: String
    let title: String
    let snippet: String
    let score: Double
}

/// Vault 全体を対象にした素朴な全文検索。
///
/// 数千ノート程度ならメモリ上の走査で十分速い。規模が大きくなったら
/// SQLite FTS5 やベクトル検索に差し替える前提で、入口をここに集めている。
nonisolated enum SearchEngine {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// 空白区切りの語をすべて含むノートを返す（AND 検索）。
    static func search(_ query: String, in notes: [Note], limit: Int = 200) -> [SearchHit] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for note in notes {
            var score = 0.0
            var matchedAll = true
            for term in terms {
                let inTitle = note.title.range(of: term, options: options) != nil
                let inTags = note.tags.contains { $0.range(of: term, options: options) != nil }
                let bodyCount = occurrences(of: term, in: note.content, cap: 20)
                if !inTitle, !inTags, bodyCount == 0 {
                    matchedAll = false
                    break
                }
                score += (inTitle ? 10 : 0) + (inTags ? 5 : 0) + Double(bodyCount)
            }
            guard matchedAll else { continue }
            hits.append(SearchHit(
                noteID: note.id,
                title: note.title,
                snippet: snippet(for: terms[0], in: note.body) ?? note.excerpt,
                score: score
            ))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// AI に渡す文脈を集めるための検索。
    ///
    /// 自然文の質問は空白で区切られていない（特に日本語）ので、形態素に分けてから
    /// どれか一つでも含むノートを IDF 風の重みで順位付けする（OR 検索）。
    static func retrieve(for question: String, in notes: [Note], limit: Int) -> [SearchHit] {
        let terms = keywords(in: question)
        guard !terms.isEmpty, !notes.isEmpty else { return [] }

        let n = Double(notes.count)
        var counts: [String: [Int]] = [:]
        for term in terms {
            counts[term] = notes.map { note in
                occurrences(of: term, in: note.content, cap: 10) + (note.title.range(of: term, options: options) != nil ? 5 : 0)
            }
        }

        var hits: [SearchHit] = []
        for (index, note) in notes.enumerated() {
            var score = 0.0
            var best: (term: String, weight: Double)?
            for term in terms {
                let count = counts[term]![index]
                guard count > 0 else { continue }
                let df = Double(counts[term]!.filter { $0 > 0 }.count)
                let idf = log((n + 1) / df) + 1
                let weight = idf * (1 + log(Double(count)))
                score += weight
                if weight > best?.weight ?? 0 { best = (term, weight) }
            }
            guard score > 0 else { continue }
            hits.append(SearchHit(
                noteID: note.id,
                title: note.title,
                snippet: best.flatMap { snippet(for: $0.term, in: note.body) } ?? note.excerpt,
                score: score
            ))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// 質問文から検索に使う語を取り出す。助詞などの短いひらがなや記号は捨てる。
    static func keywords(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            words.append(String(text[range]))
            return true
        }

        let stopwords: Set<String> = [
            "the", "and", "for", "what", "how", "about", "with", "this", "that", "are", "is",
            "について", "こと", "もの", "ため", "よう", "これ", "それ", "あれ", "どれ", "なに", "何",
            "教え", "ください", "ノート", "メモ", "まとめ", "書い", "ある", "いる", "する", "した",
        ]
        var seen = Set<String>()
        return words.filter { word in
            let lower = word.lowercased()
            guard !stopwords.contains(lower), seen.insert(lower).inserted else { return false }
            if word.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) }) {
                return false
            }
            let isHiraganaOnly = word.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
            if isHiraganaOnly { return word.count >= 3 }
            let isASCII = word.unicodeScalars.allSatisfy(\.isASCII)
            return isASCII ? word.count >= 3 : word.count >= 1
        }
    }

    static func occurrences(of term: String, in text: String, cap: Int) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while count < cap, let r = text.range(of: term, options: options, range: searchRange) {
            count += 1
            searchRange = r.upperBound..<text.endIndex
        }
        return count
    }

    /// 一致箇所の前後を切り出す。
    static func snippet(for term: String, in text: String, radius: Int = 50) -> String? {
        guard let r = text.range(of: term, options: options) else { return nil }
        let start = text.index(r.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let piece = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + piece + (end < text.endIndex ? "…" : "")
    }
}
