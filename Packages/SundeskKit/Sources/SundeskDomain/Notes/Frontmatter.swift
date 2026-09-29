//
//  Frontmatter.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// ノート先頭の YAML フロントマター。
///
/// YAML の全機能ではなく、ノートのプロパティで使う範囲（文字列、インラインの配列 `[a, b]`、
/// `- 要素` の配列）だけを読む。入れ子のマップなど読めない値は、原文のまま文字列にする。
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

    public static func parse(_ yaml: String) -> [NoteProperty] {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var properties: [NoteProperty] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), line.first?.isWhitespace != true,
                let colon = line.firstIndex(of: ":")
            else { continue }

            let key = unquote(line[..<colon].trimmingCharacters(in: .whitespaces))
            let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if rest.isEmpty {
                // 続く `- 要素` の行（またはインデントされた行）をまとめて読む
                var block: [String] = []
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    guard !nextTrimmed.isEmpty, next.first?.isWhitespace == true || nextTrimmed.hasPrefix("- ") else {
                        break
                    }
                    block.append(nextTrimmed)
                    index += 1
                }
                if !block.isEmpty, block.allSatisfy({ $0.hasPrefix("- ") }) {
                    let items = block.map { unquote(String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces)) }
                    properties.append(NoteProperty(key: key, value: .list(items.filter { !$0.isEmpty })))
                } else {
                    properties.append(NoteProperty(key: key, value: .text(block.joined(separator: "\n"))))
                }
            } else if rest.hasPrefix("["), rest.hasSuffix("]") {
                let items = rest.dropFirst().dropLast().split(separator: ",")
                    .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
                properties.append(NoteProperty(key: key, value: .list(items)))
            } else {
                properties.append(NoteProperty(key: key, value: .text(unquote(rest))))
            }
        }
        return properties
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
