//
//  ReferenceIdentifier.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 書誌情報を引ける識別子。
public enum ReferenceIdentifier: Equatable, Hashable, Sendable {
    case doi(String)
    /// arXiv の ID（版の番号「v2」は付けない）。
    case arxiv(String)
    /// ハイフンを除いた ISBN。
    case isbn(String)

    /// 入力された文字列を読む。URL や「doi:」「arXiv:」「ISBN」の接頭辞が付いていてもよい。
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: /(?i)(?:doi:\s*|https?:\/\/(?:dx\.)?doi\.org\/)?(10\.\d{4,9}\/\S+)/) {
            self = .doi(Self.trimTrailingPunctuation(String(match.output.1)))
        } else if let match = trimmed.wholeMatch(
            of: /(?i)(?:arxiv:\s*|https?:\/\/arxiv\.org\/(?:abs|pdf)\/)?(\d{4}\.\d{4,5})(?:v\d+)?(?:\.pdf)?/)
        {
            self = .arxiv(String(match.output.1))
        } else if let match = trimmed.wholeMatch(
            of: /(?i)(?:arxiv:\s*|https?:\/\/arxiv\.org\/(?:abs|pdf)\/)?([a-z\-]+(?:\.[a-z]{2})?\/\d{7})(?:v\d+)?/)
        {
            self = .arxiv(String(match.output.1))
        } else if let isbn = Self.isbn(in: trimmed) {
            self = .isbn(isbn)
        } else {
            return nil
        }
    }

    /// 画面に出す形（「DOI 10.1038/ncomms5213」）。
    public var text: String {
        switch self {
        case .doi(let value): "DOI \(value)"
        case .arxiv(let value): "arXiv:\(value)"
        case .isbn(let value): "ISBN \(value)"
        }
    }

    private static func trimTrailingPunctuation(_ doi: String) -> String {
        var result = doi
        while let last = result.last, ".,;)]".contains(last) { result.removeLast() }
        return result
    }

    /// 検査の数字が合う ISBN-10 か ISBN-13。
    private static func isbn(in text: String) -> String? {
        var body = text.uppercased()
        if body.hasPrefix("ISBN") { body = String(body.dropFirst(4)) }
        let characters = body.filter { $0 != "-" && $0 != " " && $0 != ":" }
        guard characters.allSatisfy({ $0.isNumber || $0 == "X" }) else { return nil }
        let digits = characters.map { $0 == "X" ? 10 : $0.wholeNumberValue ?? 0 }
        switch digits.count {
        case 10:
            let sum = digits.enumerated().reduce(0) { $0 + (10 - $1.offset) * $1.element }
            return sum % 11 == 0 ? characters : nil
        case 13:
            guard !characters.contains("X") else { return nil }
            let sum = digits.enumerated().reduce(0) { $0 + ($1.offset.isMultiple(of: 2) ? 1 : 3) * $1.element }
            return sum % 10 == 0 ? characters : nil
        default:
            return nil
        }
    }
}
