//
//  SwiftMarkdownParser.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Markdown
import SundeskDomain

/// ノートを swift-markdown で解析し、索引に必要な情報（タイトル、タグ、リンク、見出し）を取り出す。
///
/// Domain の `MarkdownParsing` の実装。コードの範囲と見出し、通常のリンクは swift-markdown の構文木から、
/// CommonMark にない記法（数式、`[[リンク]]`、`#タグ`）はコードを伏せた本文から見つける。
public struct SwiftMarkdownParser: MarkdownParsing {
    public init() {}

    public func analyze(_ source: String, path: String) -> NoteAnalysis {
        let (yaml, body) = Frontmatter.split(source)
        let properties = yaml.map(Frontmatter.parse) ?? []
        let lineOffset = Self.lineCount(source) - Self.lineCount(body)

        let document = Document(parsing: body)
        var collector = AnalysisCollector(map: SourceMap(body))
        collector.visit(document)

        let withoutCode = MarkdownPatterns.mask(body, ranges: collector.codeRanges)
        let prose = MarkdownPatterns.mask(withoutCode, ranges: MarkdownPatterns.math(in: withoutCode).map(\.range))

        let title = properties.first { $0.key == "title" }.flatMap(\.value.firstText) ?? collector.firstLevelOneHeading

        var tags: [String] = []
        for property in properties where property.key == "tags" || property.key == "tag" {
            switch property.value {
            case .list(let items): tags += items
            case .text(let text): tags += text.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            }
        }
        tags += MarkdownPatterns.tags(in: prose).map(\.name)

        let wikilinks = MarkdownPatterns.wikilinks(in: prose).map {
            NoteLinkReference(target: $0.target, isExactPath: false)
        }
        let relativeLinks = collector.linkDestinations.compactMap { href -> NoteLinkReference? in
            guard !href.hasPrefix("#"), href.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) == nil,
                let resolved = VaultPath.resolve(href, from: path)
            else { return nil }
            return NoteLinkReference(target: resolved, isExactPath: true)
        }

        return NoteAnalysis(
            title: title,
            properties: properties,
            tags: Self.unique(tags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }),
            links: Self.unique(wikilinks + relativeLinks),
            headings: collector.headings.map {
                NoteHeading(level: $0.level, text: $0.text, line: $0.line + lineOffset)
            },
            body: body
        )
    }

    private static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}

/// 構文木から、コードの範囲、見出し、通常のリンクの行き先を集める。
private struct AnalysisCollector: MarkupWalker {
    let map: SourceMap
    var codeRanges: [NSRange] = []
    /// 見出し（行番号は本文の中での行。フロントマターの分はあとで足す）。
    var headings: [NoteHeading] = []
    var linkDestinations: [String] = []

    var firstLevelOneHeading: String? {
        headings.first { $0.level == 1 }?.text
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = map.range(codeBlock.range) { codeRanges.append(range) }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if let range = map.range(inlineCode.range) { codeRanges.append(range) }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if let range = map.range(html.range) { codeRanges.append(range) }
    }

    mutating func visitHeading(_ heading: Heading) {
        let text = heading.plainText.trimmingCharacters(in: .whitespaces)
        if let line = heading.range?.lowerBound.line, !text.isEmpty {
            headings.append(NoteHeading(level: heading.level, text: text, line: line))
        }
        descendInto(heading)
    }

    mutating func visitLink(_ link: Link) {
        if let destination = link.destination, !destination.isEmpty { linkDestinations.append(destination) }
        descendInto(link)
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
