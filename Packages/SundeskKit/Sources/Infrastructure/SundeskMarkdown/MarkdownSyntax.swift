//
//  MarkdownSyntax.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Markdown
import SundeskDomain

/// エディタで色や書体を変える範囲。範囲は UTF-16（NSTextView と同じ単位）で、ノート全体での位置。
public struct MarkdownSyntaxSpan: Equatable, Sendable {
    public let range: NSRange
    public let role: MarkdownSyntaxRole

    public init(range: NSRange, role: MarkdownSyntaxRole) {
        self.range = range
        self.role = role
    }
}

public enum MarkdownSyntaxRole: Equatable, Sendable {
    /// 記法の記号（`#`、`**`、`[[` など）。ライブプレビューでは、カーソルのない行で隠す。
    case syntax
    case frontmatter
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    /// フェンスの内側のコード。
    case codeBlock(language: String?)
    /// コードブロックの ``` の行。
    case codeFence
    /// リンクの文字。`target` は押したときの行き先。
    case link(MarkdownLinkTarget?)
    case wikilink(target: String)
    case image
    case math(display: Bool)
    case tag
    case quote
    /// 引用の `>`。
    case quoteMarker
    /// 箇条書きの `-` や `1.`。
    case listMarker
    /// タスクの `[ ]`、`[x]`。
    case taskMarker(checked: Bool)
    case rule
    /// 表の `|` と区切りの行。
    case tableDelimiter
    case html
}

/// エディタのための、記法の範囲を見つける。
public enum MarkdownSyntax {
    /// - Parameter notePath: 相対リンクを解決するときの基準（Vault のルートからのパス）。
    public static func spans(in source: String, notePath: String = "") -> [MarkdownSyntaxSpan] {
        let body = Frontmatter.split(source).body
        let base = (source as NSString).length - (body as NSString).length
        var spans: [MarkdownSyntaxSpan] = []
        if base > 0 {
            spans.append(MarkdownSyntaxSpan(range: NSRange(location: 0, length: base), role: .frontmatter))
        }

        // 数式と [[リンク]] を先に見つけ、構文の解析では空白に伏せる（`_` や `|` を誤って読まないように）
        let codeRanges = CodeRanges.find(in: body)
        let withoutCode = MarkdownPatterns.mask(body, ranges: codeRanges)
        let math = MarkdownPatterns.math(in: withoutCode)
        let withoutMath = MarkdownPatterns.mask(withoutCode, ranges: math.map(\.range))
        let wikilinks = MarkdownPatterns.wikilinks(in: withoutMath)
        let prose = MarkdownPatterns.mask(withoutMath, ranges: wikilinks.map(\.range))
        let masked = MarkdownPatterns.mask(body, ranges: math.map(\.range) + wikilinks.map(\.range))

        var collector = SyntaxCollector(
            text: masked as NSString, map: SourceMap(masked, base: base), notePath: notePath)
        collector.visit(Document(parsing: masked))
        spans += collector.spans

        for item in math {
            let range = item.range.shifted(by: base)
            let marker = item.isDisplay ? 2 : 1
            spans.append(MarkdownSyntaxSpan(range: range, role: .math(display: item.isDisplay)))
            spans.append(MarkdownSyntaxSpan(range: NSRange(location: range.location, length: marker), role: .syntax))
            spans.append(
                MarkdownSyntaxSpan(range: NSRange(location: NSMaxRange(range) - marker, length: marker), role: .syntax))
        }
        for link in wikilinks {
            let range = link.range.shifted(by: base)
            let label = link.labelRange.shifted(by: base)
            spans.append(MarkdownSyntaxSpan(range: label, role: .wikilink(target: link.target)))
            spans.append(
                MarkdownSyntaxSpan(
                    range: NSRange(location: range.location, length: label.location - range.location), role: .syntax))
            spans.append(
                MarkdownSyntaxSpan(
                    range: NSRange(location: NSMaxRange(label), length: NSMaxRange(range) - NSMaxRange(label)),
                    role: .syntax))
        }
        for tag in MarkdownPatterns.tags(in: prose) {
            spans.append(MarkdownSyntaxSpan(range: tag.range.shifted(by: base), role: .tag))
        }
        return spans.filter { $0.range.length > 0 }.sorted { $0.range.location < $1.range.location }
    }
}

extension NSRange {
    fileprivate func shifted(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}

enum CodeRanges {
    /// コード（フェンスとインラインコード）の範囲。
    static func find(in text: String) -> [NSRange] {
        var collector = Collector(map: SourceMap(text))
        collector.visit(Document(parsing: text))
        return collector.ranges
    }

    private struct Collector: MarkupWalker {
        let map: SourceMap
        var ranges: [NSRange] = []

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            if let range = map.range(codeBlock.range) { ranges.append(range) }
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            if let range = map.range(inlineCode.range) { ranges.append(range) }
        }
    }
}

/// 構文木をたどって、ブロックとインラインの範囲、記法の記号の範囲を集める。
private struct SyntaxCollector: MarkupWalker {
    /// 本文（数式と [[リンク]] を伏せたもの）。位置は `map.base` を足すとノート全体での位置になる。
    let text: NSString
    let map: SourceMap
    let notePath: String
    var spans: [MarkdownSyntaxSpan] = []

    private mutating func add(_ range: NSRange?, _ role: MarkdownSyntaxRole) {
        guard let range, range.length > 0 else { return }
        spans.append(MarkdownSyntaxSpan(range: range, role: role))
    }

    /// 要素の範囲のうち、子の前と後ろ（記法の記号）。
    private mutating func addSurroundingSyntax(_ markup: Markup) {
        guard let range = map.range(markup.range),
            let first = markup.children.first(where: { _ in true }), let firstRange = map.range(first.range),
            let lastRange = map.range(Array(markup.children).last?.range)
        else { return }
        add(NSRange(location: range.location, length: firstRange.location - range.location), .syntax)
        add(NSRange(location: NSMaxRange(lastRange), length: NSMaxRange(range) - NSMaxRange(lastRange)), .syntax)
    }

    /// ノート全体での位置を、`text` の中の位置にする。
    private func local(_ range: NSRange) -> NSRange {
        NSRange(location: range.location - map.base, length: range.length)
    }

    // MARK: - ブロック

    mutating func visitHeading(_ heading: Heading) {
        guard let range = map.range(heading.range) else { return }
        add(range, .heading(level: heading.level))
        let isATX = text.substring(with: local(range)).trimmingCharacters(in: .whitespaces).hasPrefix("#")
        if isATX {
            // `## ` の部分。見出しが空なら行全体
            let end = map.range(heading.children.first(where: { _ in true })?.range)?.location ?? NSMaxRange(range)
            add(NSRange(location: range.location, length: end - range.location), .syntax)
        } else if let lastRange = map.range(Array(heading.children).last?.range) {
            // 下線の行（`===` や `---`）
            add(NSRange(location: NSMaxRange(lastRange), length: NSMaxRange(range) - NSMaxRange(lastRange)), .syntax)
        }
        descendInto(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = map.range(codeBlock.range) else { return }
        let lines = lineRanges(in: range)
        let isFenced = lines.first.map { isFence(local($0)) } ?? false
        guard isFenced, let first = lines.first else {
            add(range, .codeBlock(language: nil))
            return
        }
        add(first, .codeFence)
        var content = lines.dropFirst()
        if let last = content.last, isFence(local(last)) {
            add(last, .codeFence)
            content = content.dropLast()
        }
        if let lower = content.first?.location, let upper = content.last.map(NSMaxRange) {
            add(NSRange(location: lower, length: upper - lower), .codeBlock(language: codeBlock.language))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = map.range(blockQuote.range) else { return }
        add(range, .quote)
        for line in lineRanges(in: range) {
            let marker = text.range(of: #"^[ \t]*(>[ \t]?)+"#, options: .regularExpression, range: local(line))
            if marker.location != NSNotFound {
                add(NSRange(location: marker.location + map.base, length: marker.length), .quoteMarker)
            }
        }
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        guard let range = map.range(listItem.range) else { return }
        let firstChild = map.range(listItem.children.first(where: { _ in true })?.range)
        let lineEnd = NSMaxRange(text.lineRange(for: NSRange(location: local(range).location, length: 0))) + map.base
        let markerEnd = min(firstChild?.location ?? lineEnd, lineEnd)
        let marker = NSRange(location: range.location, length: markerEnd - range.location)
        if let checkbox = listItem.checkbox {
            let box = text.range(of: #"\[[ xX]\]"#, options: .regularExpression, range: local(marker))
            if box.location != NSNotFound {
                add(NSRange(location: range.location, length: box.location + map.base - range.location), .listMarker)
                add(
                    NSRange(location: box.location + map.base, length: box.length),
                    .taskMarker(checked: checkbox == .checked))
            } else {
                add(marker, .listMarker)
            }
        } else {
            add(marker, .listMarker)
        }
        descendInto(listItem)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        add(map.range(thematicBreak.range), .rule)
    }

    mutating func visitTable(_ table: Table) {
        guard let range = map.range(table.range) else { return }
        let lines = lineRanges(in: range)
        if lines.count > 1 { add(lines[1], .tableDelimiter) }
        for (index, line) in lines.enumerated() where index != 1 {
            let string = text.substring(with: local(line)) as NSString
            var previous: unichar = 0
            for offset in 0..<string.length {
                let character = string.character(at: offset)
                if character == 0x7C, previous != 0x5C {  // `|`（`\|` は除く）
                    add(NSRange(location: line.location + offset, length: 1), .tableDelimiter)
                }
                previous = character
            }
        }
        descendInto(table)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        add(map.range(html.range), .html)
    }

    // MARK: - インライン

    mutating func visitStrong(_ strong: Strong) {
        add(map.range(strong.range), .strong)
        addSurroundingSyntax(strong)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        add(map.range(emphasis.range), .emphasis)
        addSurroundingSyntax(emphasis)
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        add(map.range(strikethrough.range), .strikethrough)
        addSurroundingSyntax(strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = map.range(inlineCode.range) else { return }
        add(range, .inlineCode)
        let content = text.substring(with: local(range))
        let ticks = content.prefix { $0 == "`" }.utf16.count
        guard ticks > 0, range.length > ticks * 2 else { return }
        add(NSRange(location: range.location, length: ticks), .syntax)
        add(NSRange(location: NSMaxRange(range) - ticks, length: ticks), .syntax)
    }

    mutating func visitLink(_ link: Link) {
        guard let range = map.range(link.range) else { return }
        let destination = link.destination ?? ""
        let target = LinkTarget.classify(destination, notePath: notePath)
        if let firstRange = map.range(link.children.first(where: { _ in true })?.range),
            let lastRange = map.range(Array(link.children).last?.range)
        {
            add(
                NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location),
                .link(target))
            addSurroundingSyntax(link)
        } else {
            add(range, .link(target))
        }
    }

    mutating func visitImage(_ image: Image) {
        add(map.range(image.range), .image)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        add(map.range(inlineHTML.range), .html)
    }

    // MARK: - 補助

    /// 範囲に含まれる各行の範囲（改行を除く。ノート全体での位置）。
    private func lineRanges(in range: NSRange) -> [NSRange] {
        var lines: [NSRange] = []
        let local = local(range)
        var location = local.location
        while location < NSMaxRange(local) {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let upper = min(contentsEnd, NSMaxRange(local))
            lines.append(NSRange(location: start + map.base, length: max(upper - start, 0)))
            guard end > location else { break }
            location = end
        }
        return lines
    }

    private func isFence(_ localRange: NSRange) -> Bool {
        let line = text.substring(with: localRange).trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("```") || line.hasPrefix("~~~")
    }
}

/// リンクの行き先の分類（閲覧表示とエディタで共通）。
enum LinkTarget {
    static func classify(_ destination: String, notePath: String) -> MarkdownLinkTarget? {
        if destination.hasPrefix("#") { return .anchor(String(destination.dropFirst())) }
        if destination.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) != nil {
            return URL(string: destination).map(MarkdownLinkTarget.external)
        }
        return VaultPath.resolve(destination, from: notePath).map(MarkdownLinkTarget.vault)
    }
}
