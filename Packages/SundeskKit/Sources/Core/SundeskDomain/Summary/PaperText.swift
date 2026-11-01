//
//  PaperText.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 要約のために、PDF の文字を整えて区切る。
public enum PaperText {
    /// 参考文献の節より前のページ。参考文献を読ませても要約の役に立たないので落とす。
    public static func body(of pages: [String]) -> [String] {
        // 1 ページ目に目次として「References」が出ることがあるので、2 ページ目から探す
        for (pageIndex, page) in pages.enumerated().dropFirst() {
            let lines = page.split(separator: "\n", omittingEmptySubsequences: false)
            guard let lineIndex = lines.firstIndex(where: isReferencesHeading) else { continue }
            let rest = lines[..<lineIndex].joined(separator: "\n")
            let isRestEmpty = rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return Array(pages[..<pageIndex]) + (isRestEmpty ? [] : [rest])
        }
        return pages
    }

    /// 上限に収まるように、ページを順に詰めて区切る。1 ページで上限を超えるときは、行の途中で分ける。
    public static func parts(
        of pages: [String], budget: Int, tokenCount: (String) async throws(SummaryError) -> Int
    ) async throws(SummaryError) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        var currentTokens = 0
        for page in pages where !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for (piece, tokens) in try await pieces(of: page, budget: budget, tokenCount: tokenCount) {
                if currentTokens + tokens > budget, !current.isEmpty {
                    parts.append(current.joined(separator: "\n"))
                    current = []
                    currentTokens = 0
                }
                current.append(piece)
                currentTokens += tokens
            }
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n")) }
        return parts
    }

    /// 上限に収まるまで半分に分けた、文とそのトークン数。
    private static func pieces(
        of text: String, budget: Int, tokenCount: (String) async throws(SummaryError) -> Int
    ) async throws(SummaryError) -> [(String, Int)] {
        let tokens = try await tokenCount(text)
        guard tokens > budget, text.count > 1 else { return [(text, tokens)] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let middle = lines.count / 2
        let halves: [String] =
            if lines.count > 1 {
                [lines[..<middle].joined(separator: "\n"), lines[middle...].joined(separator: "\n")]
            } else {
                [String(text.prefix(text.count / 2)), String(text.dropFirst(text.count / 2))]
            }
        var result: [(String, Int)] = []
        for half in halves {
            result += try await pieces(of: half, budget: budget, tokenCount: tokenCount)
        }
        return result
    }

    private static func isReferencesHeading(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(?i)(?:\d+\.?\s*)?(?:references|bibliography|参考文献|引用文献)/) != nil
    }
}
