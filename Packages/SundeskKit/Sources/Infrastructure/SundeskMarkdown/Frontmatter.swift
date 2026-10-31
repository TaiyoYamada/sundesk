//
//  Frontmatter.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// ノート先頭の YAML フロントマター。中身は読まず、本文と分けるだけ。
public enum Frontmatter {
    /// フロントマター（`---` の内側）と本文に分ける。フロントマターがなければ nil と全文。
    public static func split(_ source: String) -> (frontmatter: String?, body: String) {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return (nil, source) }
        lines.removeFirst()
        guard
            let closing = lines.firstIndex(where: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed == "---" || trimmed == "..."
            })
        else { return (nil, source) }

        let yaml = lines[..<closing].map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }.joined(separator: "\n")
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return (yaml, body)
    }
}
