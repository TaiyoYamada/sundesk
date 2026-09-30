//
//  MarkdownDocument.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Markdown
import SundeskDomain

/// 閲覧表示のための、ノートのブロックの並び。
public struct MarkdownDocument: Equatable, Sendable {
    public let blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

public indirect enum MarkdownBlock: Equatable, Sendable {
    /// `index` は何番目の見出しか（0 始まり）。目次から飛ぶときに使う。
    case heading(level: Int, content: [MarkdownInline], index: Int)
    case paragraph([MarkdownInline])
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    /// Obsidian の注記（`> [!note] 見出し`）。
    case callout(kind: String, title: String, content: [MarkdownBlock])
    case code(language: String?, code: String)
    case math(String)
    case table(header: [[MarkdownInline]], rows: [[[MarkdownInline]]], alignments: [MarkdownTableAlignment])
    case image(MarkdownImage)
    case rule
    case html(String)
}

public struct MarkdownListItem: Equatable, Sendable {
    /// タスクリストなら、済んでいるか。普通の項目なら nil。
    public let checkbox: Bool?
    public let blocks: [MarkdownBlock]

    public init(checkbox: Bool?, blocks: [MarkdownBlock]) {
        self.checkbox = checkbox
        self.blocks = blocks
    }
}

public enum MarkdownTableAlignment: Equatable, Sendable {
    case leading, center, trailing
}

public struct MarkdownImage: Equatable, Sendable {
    public let source: MarkdownLinkTarget
    public let alt: String

    public init(source: MarkdownLinkTarget, alt: String) {
        self.source = source
        self.alt = alt
    }
}

public indirect enum MarkdownInline: Equatable, Sendable {
    case text(String)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(target: MarkdownLinkTarget, content: [MarkdownInline])
    /// `[[リンク先|表示名]]`。
    case wikilink(target: String, label: String)
    case math(String)
    case tag(String)
    case image(MarkdownImage)
    case lineBreak
    case softBreak
}

public enum MarkdownLinkTarget: Equatable, Sendable {
    /// http など、アプリの外で開くもの。
    case external(URL)
    /// Vault の中のファイル（Vault のルートからのパス）。
    case vault(String)
    /// 同じノートの中の見出しなど。
    case anchor(String)
}

// MARK: - 組み立て

extension MarkdownInline {
    /// 書式を除いた文字列。
    public var plainText: String {
        switch self {
        case .text(let text), .code(let text): text
        case .strong(let content), .emphasis(let content), .strikethrough(let content), .link(_, let content):
            content.map(\.plainText).joined()
        case .wikilink(_, let label): label
        case .math(let latex): latex
        case .tag(let name): "#" + name
        case .image(let image): image.alt
        case .lineBreak, .softBreak: " "
        }
    }
}

/// ノートを閲覧表示のための構造にする。
public enum MarkdownDocumentParser {
    /// - Parameter notePath: Vault のルートからのパス。相対リンクと画像の解決に使う。
    public static func parse(_ source: String, notePath: String) -> MarkdownDocument {
        let body = Frontmatter.split(source).body
        let protected = Placeholders.protect(body)
        let document = Document(parsing: protected.text)
        var builder = Builder(notePath: notePath, placeholders: protected)
        return MarkdownDocument(blocks: builder.blocks(from: document.children))
    }
}

/// 数式と `[[リンク]]` を、swift-markdown に渡す前に目印（私用領域の文字）に置き換える。
///
/// そのまま渡すと、数式の `\\` や `_`、表の中の `|` が Markdown として解釈されて壊れる。
struct Placeholders {
    static let open: Character = "\u{E000}"
    static let close: Character = "\u{E001}"

    let text: String
    var math: [String] = []
    var displayMath: [String] = []
    var wikilinks: [(target: String, label: String)] = []

    static func protect(_ body: String) -> Placeholders {
        // コード（フェンスとインラインコード）の中は置き換えない
        let codeRanges = CodeRanges.find(in: body)
        let withoutCode = MarkdownPatterns.mask(body, ranges: codeRanges)

        var replacements: [(range: NSRange, text: String)] = []
        var result = Placeholders(text: "")
        for math in MarkdownPatterns.math(in: withoutCode) {
            if math.isDisplay {
                result.displayMath.append(math.latex.trimmingCharacters(in: .whitespacesAndNewlines))
                replacements.append((math.range, "\(open)D\(result.displayMath.count - 1)\(close)"))
            } else {
                result.math.append(math.latex)
                replacements.append((math.range, "\(open)M\(result.math.count - 1)\(close)"))
            }
        }
        let mathMasked = MarkdownPatterns.mask(withoutCode, ranges: replacements.map(\.range))
        for link in MarkdownPatterns.wikilinks(in: mathMasked) {
            result.wikilinks.append((link.target, link.label))
            replacements.append((link.range, "\(open)W\(result.wikilinks.count - 1)\(close)"))
        }

        let string = NSMutableString(string: body)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            string.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return Placeholders(
            text: string as String, math: result.math, displayMath: result.displayMath, wikilinks: result.wikilinks)
    }

    /// 目印を含むテキストを、テキストと数式・リンクの並びに戻す。
    func inlines(from text: String) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var buffer = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == Self.open, let end = text[index...].firstIndex(of: Self.close) {
                let token = text[text.index(after: index)..<end]
                if let kind = token.first, let number = Int(token.dropFirst()) {
                    if !buffer.isEmpty { result.append(.text(buffer)) }
                    buffer = ""
                    switch kind {
                    case "M" where math.indices.contains(number): result.append(.math(math[number]))
                    case "D" where displayMath.indices.contains(number): result.append(.math(displayMath[number]))
                    case "W" where wikilinks.indices.contains(number):
                        result.append(.wikilink(target: wikilinks[number].target, label: wikilinks[number].label))
                    default: break
                    }
                    index = text.index(after: end)
                    continue
                }
            }
            buffer.append(text[index])
            index = text.index(after: index)
        }
        if !buffer.isEmpty { result.append(.text(buffer)) }
        return result
    }

    /// 段落がディスプレイ数式の目印だけなら、その数式。
    func displayMath(in paragraph: Paragraph) -> String? {
        let text = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.first == Self.open, text.last == Self.close, text.dropFirst().first == "D",
            let number = Int(text.dropFirst(2).dropLast()), displayMath.indices.contains(number)
        else { return nil }
        return displayMath[number]
    }
}

/// swift-markdown の構文木を、閲覧表示のための構造に直す。
private struct Builder {
    let notePath: String
    let placeholders: Placeholders
    var headingCount = 0

    mutating func blocks(from children: some Sequence<Markup>) -> [MarkdownBlock] {
        children.compactMap { block(from: $0) }
    }

    mutating func block(from markup: Markup) -> MarkdownBlock? {
        switch markup {
        case let heading as Heading:
            defer { headingCount += 1 }
            return .heading(level: heading.level, content: inlines(from: heading.children), index: headingCount)
        case let paragraph as Paragraph:
            if let latex = placeholders.displayMath(in: paragraph) { return .math(latex) }
            let content = inlines(from: paragraph.children)
            if content.count == 1, case .image(let image) = content[0] { return .image(image) }
            return .paragraph(content)
        case let list as UnorderedList:
            return .list(ordered: false, start: 1, items: list.listItems.map { listItem(from: $0) })
        case let list as OrderedList:
            return .list(ordered: true, start: Int(list.startIndex), items: list.listItems.map { listItem(from: $0) })
        case let quote as BlockQuote:
            return self.quote(quote)
        case let code as CodeBlock:
            let text = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            if code.language?.lowercased() == "math" { return .math(text) }
            return .code(language: code.language, code: text)
        case let table as Table:
            return .table(
                header: table.head.cells.map { inlines(from: $0.children) },
                rows: table.body.rows.map { row in row.cells.map { inlines(from: $0.children) } },
                alignments: table.columnAlignments.map { alignment in
                    switch alignment {
                    case .center: .center
                    case .right: .trailing
                    case .left, nil: .leading
                    }
                }
            )
        case is ThematicBreak:
            return .rule
        case let html as HTMLBlock:
            return .html(html.rawHTML)
        default:
            return nil
        }
    }

    mutating func listItem(from item: ListItem) -> MarkdownListItem {
        let checkbox: Bool? =
            switch item.checkbox {
            case .checked: true
            case .unchecked: false
            case nil: nil
            }
        return MarkdownListItem(checkbox: checkbox, blocks: blocks(from: item.children))
    }

    /// 最初の行が `[!kind] 見出し` なら注記、そうでなければ普通の引用。
    mutating func quote(_ quote: BlockQuote) -> MarkdownBlock {
        var children = Array(quote.children)
        guard let first = children.first as? Paragraph else { return .quote(blocks(from: children)) }
        // 1 行目（最初の改行まで）だけを見る
        let firstParagraphInlines = inlines(from: first.children)
        let breakIndex = firstParagraphInlines.firstIndex { $0 == .softBreak || $0 == .lineBreak }
        let firstLine = firstParagraphInlines[..<(breakIndex ?? firstParagraphInlines.endIndex)].map(\.plainText)
            .joined()
        guard let match = firstLine.wholeMatch(of: /\[!([A-Za-z-]+)\][+-]?[ \t]*(.*)/) else {
            return .quote(blocks(from: children))
        }
        let kind = String(match.output.1).lowercased()
        let title = String(match.output.2).trimmingCharacters(in: .whitespaces)

        // 最初の段落から 1 行目を取り除く
        var rest: [MarkdownBlock] = []
        if let breakIndex {
            let remaining = Array(firstParagraphInlines[(breakIndex + 1)...])
            if !remaining.isEmpty { rest.append(.paragraph(remaining)) }
        }
        children.removeFirst()
        rest += blocks(from: children)
        return .callout(kind: kind, title: title.isEmpty ? CalloutKind.label(for: kind) : title, content: rest)
    }

    func inlines(from children: some Sequence<Markup>) -> [MarkdownInline] {
        children.flatMap { inline(from: $0) }
    }

    func inline(from markup: Markup) -> [MarkdownInline] {
        switch markup {
        case let text as Text:
            return splitTags(placeholders.inlines(from: text.string))
        case let strong as Strong:
            return [.strong(inlines(from: strong.children))]
        case let emphasis as Emphasis:
            return [.emphasis(inlines(from: emphasis.children))]
        case let strikethrough as Strikethrough:
            return [.strikethrough(inlines(from: strikethrough.children))]
        case let code as InlineCode:
            return [.code(code.code)]
        case let link as Link:
            let content = inlines(from: link.children)
            guard let target = target(for: link.destination ?? "") else { return content }
            return [.link(target: target, content: content)]
        case let image as Image:
            guard let source = image.source, let target = target(for: source) else { return [] }
            return [.image(MarkdownImage(source: target, alt: image.plainText))]
        case is SoftBreak:
            return [.softBreak]
        case is LineBreak:
            return [.lineBreak]
        case let html as InlineHTML:
            return [.text(html.rawHTML)]
        default:
            return [.text(markup.format())]
        }
    }

    /// リンクの行き先を分類する。相対パスは Vault のルートからのパスに直す。
    func target(for destination: String) -> MarkdownLinkTarget? {
        LinkTarget.classify(destination, notePath: notePath)
    }

    /// テキストの中の `#タグ` を、タグとして分ける。
    func splitTags(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
        inlines.flatMap { inline -> [MarkdownInline] in
            guard case .text(let text) = inline else { return [inline] }
            let tags = MarkdownPatterns.tags(in: text)
            guard !tags.isEmpty else { return [inline] }
            let string = text as NSString
            var result: [MarkdownInline] = []
            var cursor = 0
            for tag in tags {
                if tag.range.location > cursor {
                    result.append(
                        .text(string.substring(with: NSRange(location: cursor, length: tag.range.location - cursor))))
                }
                result.append(.tag(tag.name))
                cursor = tag.range.location + tag.range.length
            }
            if cursor < string.length { result.append(.text(string.substring(from: cursor))) }
            return result
        }
    }
}

/// 注記の種類ごとの名前（見出しがないときに出す）。
public enum CalloutKind {
    public static func label(for kind: String) -> String {
        switch kind {
        case "note": "メモ"
        case "info": "情報"
        case "tip", "hint": "ヒント"
        case "important": "重要"
        case "warning", "attention": "注意"
        case "caution", "danger", "error": "警告"
        case "todo": "TODO"
        case "question", "faq", "help": "疑問"
        case "example": "例"
        case "quote", "cite": "引用"
        case "success", "check", "done": "完了"
        default: kind
        }
    }
}
