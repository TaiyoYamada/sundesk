//
//  MarkdownAnalyzer.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// Markdown のノートから、フロントマター、タイトル、タグ、リンクを取り出す。
///
/// 描画は WebKit の中の markdown-it が行う。ここでは索引に必要な情報だけを、
/// markdown-it と同じ規則（コードと数式の中はリンクやタグにしない）で取り出す。
public enum MarkdownAnalyzer {
    public static func analyze(_ source: String, path: String) -> NoteAnalysis {
        let (frontmatter, body) = Frontmatter.split(source)
        let properties = frontmatter.map(Frontmatter.parse) ?? []
        let prose = maskCodeAndMath(body)

        let title = properties.first { $0.key == "title" }.flatMap(\.value.firstText) ?? firstHeading(in: prose)

        var tags: [String] = []
        for property in properties where property.key == "tags" || property.key == "tag" {
            switch property.value {
            case .list(let items): tags += items
            case .text(let text): tags += text.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            }
        }
        tags += inlineTags(in: prose)

        return NoteAnalysis(
            title: title,
            properties: properties,
            tags: unique(tags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }),
            links: unique(wikilinks(in: prose) + relativeLinks(in: prose, notePath: path)),
            body: body
        )
    }

    // MARK: - 取り出し

    static func wikilinks(in prose: String) -> [NoteLinkReference] {
        prose.matches(of: /\[\[([^\[\]\n]+?)\]\]/).compactMap { match in
            let inner = String(match.output.1)
            let rawTarget = inner.split(separator: /\\?\|/, maxSplits: 1).first.map(String.init) ?? inner
            var target = rawTarget.trimmingCharacters(in: .whitespaces)
            while target.hasSuffix("\\") { target.removeLast() }
            if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
            target = target.trimmingCharacters(in: .whitespaces)
            return target.isEmpty ? nil : NoteLinkReference(target: target, isExactPath: false)
        }
    }

    static func relativeLinks(in prose: String, notePath: String) -> [NoteLinkReference] {
        prose.matches(of: /(!?)\[[^\]\n]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/).compactMap { match in
            // `![…](…)` は画像なのでリンクに数えない
            guard match.output.1.isEmpty else { return nil }
            let href = String(match.output.2)
            guard !href.hasPrefix("#"), href.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) == nil,
                let path = VaultPath.resolve(href, from: notePath)
            else { return nil }
            return NoteLinkReference(target: path, isExactPath: true)
        }
    }

    static func inlineTags(in prose: String) -> [String] {
        // `#` の直前が文字や数字なら（URL の `#` や色の指定など）タグにしない
        prose.matches(
            of: /(^|[^\p{L}\p{N}_\/&#])#([\p{L}\p{N}_\/\-]*[\p{L}_\/\-][\p{L}\p{N}_\/\-]*)/.anchorsMatchLineEndings()
        )
        .map { String($0.output.2) }
    }

    static func firstHeading(in prose: String) -> String? {
        for line in prose.split(separator: "\n", omittingEmptySubsequences: true) {
            if let match = line.wholeMatch(of: /#[ \t]+(.+?)[ \t#]*/) {
                return String(match.output.1)
            }
        }
        return nil
    }

    // MARK: - コードと数式を伏せる

    /// フェンスで囲まれたコード、インラインコード、`$$…$$`、`$…$` を空白に置き換える。
    /// 行の数は変えない。
    static func maskCodeAndMath(_ body: String) -> String {
        var lines: [Substring] = []
        var fence: Substring?
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                lines.append("")
            } else if let marker = trimmed.prefixMatch(of: /(`{3,}|~{3,})/) {
                fence = marker.output.1
                lines.append("")
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
            .replacing(/`+[^`\n]*`+/, with: " ")
            .replacing(/\$\$[\s\S]+?\$\$/, with: " ")
            .replacing(/\$([^$\n]+?)\$/) { match in
                // `$ 5 と $ 10` のように、内側の両端が空白なら数式ではない
                let inner = match.output.1
                return inner.first?.isWhitespace == true || inner.last?.isWhitespace == true ? match.output.0 : " "
            }
    }

    private static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}

extension PropertyValue {
    fileprivate var firstText: String? {
        let text: String? =
            switch self {
            case .text(let text): text
            case .list(let items): items.first
            }
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }
}
