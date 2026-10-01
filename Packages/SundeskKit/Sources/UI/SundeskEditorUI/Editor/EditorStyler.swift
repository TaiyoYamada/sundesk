//
//  EditorStyler.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskCodeHighlight
import SundeskMarkdown

/// エディタで何を色づけするか。
public enum EditorSyntax: Equatable, Sendable {
    /// Markdown。`livePreview` なら、カーソルのない行の記号を隠す（Obsidian のライブプレビュー）。
    case markdown(livePreview: Bool, notePath: String)
    /// コード。行番号を出す。
    case code(language: String)
    /// 色づけしないテキスト。
    case plain

    var isMarkdown: Bool {
        if case .markdown = self { true } else { false }
    }

    var livePreview: Bool {
        if case .markdown(let livePreview, _) = self { livePreview } else { false }
    }
}

extension NSAttributedString.Key {
    /// 押すと開くリンク（値は `LinkAttribute`）。
    static let documentLink = NSAttributedString.Key("SundeskDocumentLink")
}

/// 文字の属性に載せるリンク。
final class LinkAttribute: NSObject {
    let link: DocumentLink

    init(_ link: DocumentLink) {
        self.link = link
    }
}

/// Markdown の記法ごとに、文字の属性（書体、色）をつける。
struct MarkdownStyler {
    let livePreview: Bool
    /// 記号を見せる範囲（カーソルのある段落）。ライブプレビューでは、ここ以外の記号を隠す。
    let revealed: NSRange?

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 2
        return [.font: EditorTheme.bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    func apply(_ spans: [MarkdownSyntaxSpan], to storage: NSTextStorage) {
        storage.setAttributes(Self.baseAttributes, range: NSRange(location: 0, length: storage.length))
        // ブロック → インライン → 記号の順に重ねる（見出しの大きさの上に太字を足す、など）
        for span in spans.sorted(by: { Self.order($0.role) < Self.order($1.role) }) {
            guard NSMaxRange(span.range) <= storage.length else { continue }
            style(span, in: storage)
        }
    }

    /// 記号を隠すか。カーソルのある段落では隠さない。
    func hides(_ range: NSRange) -> Bool {
        guard livePreview else { return false }
        guard let revealed else { return true }
        return !(range.location <= NSMaxRange(revealed) && NSMaxRange(range) >= revealed.location)
    }

    private static func order(_ role: MarkdownSyntaxRole) -> Int {
        switch role {
        case .frontmatter, .heading, .quote, .codeBlock, .codeFence, .html, .rule, .tableDelimiter: 0
        case .listMarker, .taskMarker, .quoteMarker: 1
        case .syntax: 3
        default: 2
        }
    }

    private func style(_ span: MarkdownSyntaxSpan, in storage: NSTextStorage) {
        let range = span.range
        if let attributes = Self.fixedAttributes(for: span.role) {
            storage.addAttributes(attributes, range: range)
        }
        switch span.role {
        case .codeBlock(let language?):
            CodeStyler.colorTokens(in: storage, range: range, language: language)
        case .strong:
            updateFonts(in: storage, range: range) { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }
        case .inlineCode:
            updateFonts(in: storage, range: range) {
                .monospacedSystemFont(ofSize: max($0.pointSize - 1.5, EditorTheme.codeSize), weight: .regular)
            }
        case .link(let target):
            if let link = DocumentLink(target) { addLink(link, to: storage, range: range) }
        case .wikilink(let target):
            addLink(.note(target), to: storage, range: range)
        case .tag:
            let name = String((storage.string as NSString).substring(with: range).dropFirst())
            addLink(.tag(name), to: storage, range: range)
        case .syntax:
            let attributes: [NSAttributedString.Key: Any] =
                hides(range)
                ? [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]
                : [.foregroundColor: EditorTheme.syntaxColor]
            storage.addAttributes(attributes, range: range)
        default:
            break
        }
    }

    /// 記法ごとの決まった属性（書体や色）。
    private static func fixedAttributes(for role: MarkdownSyntaxRole) -> [NSAttributedString.Key: Any]? {
        switch role {
        case .frontmatter:
            [
                .font: NSFont.monospacedSystemFont(ofSize: EditorTheme.codeSize - 1, weight: .regular),
                .foregroundColor: EditorTheme.secondaryColor,
            ]
        case .heading(let level):
            [.font: EditorTheme.headingFont(level: level)]
        case .quote, .listMarker, .image:
            [.foregroundColor: EditorTheme.secondaryColor]
        case .codeBlock:
            [.font: EditorTheme.codeFont, .backgroundColor: EditorTheme.codeBackground]
        case .codeFence:
            [
                .font: EditorTheme.codeFont, .foregroundColor: EditorTheme.syntaxColor,
                .backgroundColor: EditorTheme.codeBackground,
            ]
        case .html:
            [.font: EditorTheme.codeFont, .foregroundColor: EditorTheme.secondaryColor]
        case .rule, .tableDelimiter, .quoteMarker:
            [.foregroundColor: EditorTheme.syntaxColor]
        case .taskMarker(let checked):
            [.foregroundColor: checked ? EditorTheme.tagColor : EditorTheme.secondaryColor]
        case .emphasis:
            // 日本語の書体には斜体がないので、傾きで表す
            [.obliqueness: 0.18]
        case .strikethrough:
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: EditorTheme.secondaryColor]
        case .inlineCode:
            [.backgroundColor: EditorTheme.codeBackground]
        case .link, .wikilink:
            [.foregroundColor: EditorTheme.linkColor]
        case .tag:
            [.foregroundColor: EditorTheme.tagColor]
        case .math:
            [.foregroundColor: EditorTheme.mathColor]
        case .strong, .syntax:
            nil
        }
    }

    private func addLink(_ link: DocumentLink, to storage: NSTextStorage, range: NSRange) {
        storage.addAttributes([.documentLink: LinkAttribute(link), .toolTip: "⌘ クリックで開く"], range: range)
        if livePreview, hides(range) {
            storage.addAttribute(.cursor, value: NSCursor.pointingHand, range: range)
        }
    }

    private func updateFonts(in storage: NSTextStorage, range: NSRange, _ transform: (NSFont) -> NSFont) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? EditorTheme.bodyFont
            storage.addAttribute(.font, value: transform(font), range: subrange)
        }
    }
}

/// コードのファイルと、Markdown の中のコードブロックを色づけする。
enum CodeStyler {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return [.font: EditorTheme.codeFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    static func apply(language: String?, to storage: NSTextStorage) {
        let range = NSRange(location: 0, length: storage.length)
        storage.setAttributes(baseAttributes, range: range)
        if let language {
            colorTokens(in: storage, range: range, language: language)
        }
    }

    static func colorTokens(in storage: NSTextStorage, range: NSRange, language: String) {
        let code = (storage.string as NSString).substring(with: range)
        for token in CodeHighlighter.shared.highlight(code, language: language) {
            let tokenRange = NSRange(location: range.location + token.range.location, length: token.range.length)
            guard NSMaxRange(tokenRange) <= NSMaxRange(range) else { continue }
            storage.addAttribute(.foregroundColor, value: EditorTheme.color(for: token.kind), range: tokenRange)
        }
    }
}
