//
//  BlockViews.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskCodeHighlight
import SundeskMarkdown
import SwiftUI

/// ブロックを縦に並べる。
struct BlocksView: View {
    let blocks: [MarkdownBlock]
    var spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }
}

/// 1 つのブロック。
struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let content, let index):
            InlineTextView(inlines: content, fontSize: EditorTheme.headingSize(level: level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .padding(.top, level <= 2 ? 10 : 4)
                .id(HeadingID(index: index))
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let content):
            InlineTextView(inlines: content)
        case .list(let ordered, let start, let items):
            ListBlockView(ordered: ordered, start: start, items: items)
        case .quote(let children):
            BlocksView(blocks: children)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.quaternary).frame(width: 3)
                }
        case .callout(let kind, let title, let content):
            CalloutView(kind: kind, title: title, content: content)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .math(let latex):
            DisplayMathView(latex: latex)
        case .table(let header, let rows, let alignments):
            TableBlockView(header: header, rows: rows, alignments: alignments)
        case .image(let image):
            NoteImageView(image: image)
        case .rule:
            Divider().padding(.vertical, 6)
        case .html(let html):
            Text(verbatim: html.trimmingCharacters(in: .newlines))
                .font(.system(size: EditorTheme.codeSize, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - リスト

struct ListBlockView: View {
    let ordered: Bool
    let start: Int
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item, number: start + offset)
                        .frame(minWidth: 16, alignment: .trailing)
                    BlocksView(blocks: item.blocks, spacing: 5)
                        .opacity(item.checkbox == true ? 0.6 : 1)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, number: Int) -> some View {
        if let checked = item.checkbox {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityLabel(checked ? "済み" : "未完了")
        } else if ordered {
            Text(verbatim: "\(number).")
                .font(.system(size: EditorTheme.bodySize).monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text(verbatim: "•")
                .font(.system(size: EditorTheme.bodySize, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 注記

struct CalloutView: View {
    let kind: String
    let title: String
    let content: [MarkdownBlock]

    var body: some View {
        let style = EditorTheme.callout(kind)
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: style.systemImage)
                .font(.system(size: EditorTheme.bodySize, weight: .semibold))
                .foregroundStyle(style.color)
            if !content.isEmpty {
                BlocksView(blocks: content, spacing: 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.color.opacity(0.08), in: .rect(cornerRadius: 6))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
                .fill(style.color)
                .frame(width: 3)
        }
    }
}

// MARK: - コード

struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let language, !language.isEmpty {
                    Text(verbatim: language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("コピー", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("コードをコピー")
            }
            ScrollView(.horizontal) {
                Text(CodeText.attributed(code, language: language))
                    .font(.system(size: EditorTheme.codeSize, design: .monospaced))
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(12)
        .background(Color(nsColor: EditorTheme.codeBackground), in: .rect(cornerRadius: 6))
    }
}

/// コードを tree-sitter で色づけした文字列。
enum CodeText {
    static func attributed(_ code: String, language: String?) -> AttributedString {
        var result = AttributedString(code)
        guard let language else { return result }
        for token in CodeHighlighter.shared.highlight(code, language: language) {
            guard let range = Range(token.range, in: result) else { continue }
            result[range].foregroundColor = Color(nsColor: EditorTheme.color(for: token.kind))
        }
        return result
    }
}

// MARK: - 数式

struct DisplayMathView: View {
    let latex: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let rendered = MathRenderer.shared.render(
            latex, display: true, fontSize: EditorTheme.bodySize, isDark: colorScheme == .dark)
        {
            ViewThatFits(in: .horizontal) {
                Image(nsImage: rendered.image)
                    .frame(maxWidth: .infinity)
                ScrollView(.horizontal) {
                    Image(nsImage: rendered.image)
                }
            }
            .padding(.vertical, 4)
            .accessibilityLabel(latex)
        } else {
            Text(verbatim: latex)
                .font(.system(size: EditorTheme.codeSize, design: .monospaced))
                .foregroundStyle(.red)
                .help("数式を読めませんでした")
        }
    }
}

// MARK: - 表

struct TableBlockView: View {
    let header: [[MarkdownInline]]
    let rows: [[[MarkdownInline]]]
    let alignments: [MarkdownTableAlignment]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { column, cell in
                        cellView(cell, column: column)
                            .fontWeight(.semibold)
                            .background(Color(nsColor: EditorTheme.codeBackground))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            cellView(cell, column: column)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            .clipShape(.rect(cornerRadius: 4))
        }
    }

    private func cellView(_ cell: [MarkdownInline], column: Int) -> some View {
        let alignment = column < alignments.count ? alignments[column] : .leading
        return InlineTextView(inlines: cell)
            .multilineTextAlignment(alignment.textAlignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
            .gridColumnAlignment(alignment.horizontalAlignment)
    }
}

extension MarkdownTableAlignment {
    fileprivate var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    fileprivate var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    fileprivate var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

// MARK: - 画像

struct NoteImageView: View {
    let image: MarkdownImage
    @Environment(\.readingContext) private var context
    @State private var loaded: NSImage?

    var body: some View {
        Group {
            switch image.source {
            case .vault(let path):
                if let loaded {
                    Image(nsImage: loaded)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: min(loaded.size.width, EditorTheme.readableWidth))
                } else {
                    placeholder
                        .task(id: path) { loaded = NSImage(contentsOf: context.vaultRoot.appending(path: path)) }
                }
            case .external(let url):
                AsyncImage(url: url) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                }
            case .anchor:
                placeholder
            }
        }
        .accessibilityLabel(image.alt)
    }

    private var placeholder: some View {
        Label(image.alt.isEmpty ? "画像" : image.alt, systemImage: "photo")
            .foregroundStyle(.secondary)
    }
}
