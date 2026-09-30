//
//  NotebookReadingView.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import SundeskMarkdown
import SwiftUI

/// ノートブックの 1 つのセル（描くための形）。
public struct NotebookCellContent: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case markdown(String)
        case code(source: String, executionCount: Int?, outputs: [NotebookOutputContent])
        case raw(String)
    }

    public let id: Int
    public let kind: Kind

    public init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// コードのセルの出力（描くための形）。
public enum NotebookOutputContent: Equatable, Sendable {
    case text(String)
    case image(Data)
    /// 先頭の行が見出し。`truncated` なら、行を途中までしか持っていない。
    case table(rows: [[String]], truncated: Bool)
    case error(name: String, message: String, traceback: String)
}

/// Jupyter のノートブックを、Jupyter と同じようにセルと出力を並べて読む。書き換えはしない。
public struct NotebookReadingView: View {
    private let cells: [NotebookCellContent]
    private let language: String
    private let notePath: String
    private let vaultRoot: URL
    private let onOpen: (DocumentLink) -> Void
    @State private var markdown: [Int: MarkdownDocument] = [:]
    @State private var hidesCode = false

    /// - Parameters:
    ///   - language: コードのセルの言語（色づけに使う）。
    ///   - notePath: Vault のルートからのパス（Markdown のセルの相対リンクの基準）。
    public init(
        cells: [NotebookCellContent], language: String, notePath: String, vaultRoot: URL,
        onOpen: @escaping (DocumentLink) -> Void
    ) {
        self.cells = cells
        self.language = language
        self.notePath = notePath
        self.vaultRoot = vaultRoot
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                ForEach(cells) { cell in
                    cellView(cell)
                }
            }
            .environment(\.readingContext, ReadingContext(vaultRoot: vaultRoot))
            .textSelection(.enabled)
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .environment(
            \.openURL,
            OpenURLAction { url in
                onOpen(DocumentLink(url: url))
                return .handled
            }
        )
        .task(id: cells) { markdown = await Self.parseMarkdown(cells, notePath: notePath) }
        .accessibilityIdentifier("notebook-view")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Jupyter ノートブック", systemImage: "book.pages")
            Text("\(language)・\(codeCellCount) 個のコード")
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("出力だけ見る", isOn: $hidesCode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("コードを隠して、Markdown と出力だけを並べる")
        }
        .font(.callout)
        .padding(.bottom, 4)
    }

    private var codeCellCount: Int {
        cells.count { if case .code = $0.kind { true } else { false } }
    }

    @ViewBuilder
    private func cellView(_ cell: NotebookCellContent) -> some View {
        switch cell.kind {
        case .markdown(let source):
            if let document = markdown[cell.id] {
                BlocksView(blocks: document.blocks, spacing: 10)
            } else {
                Text(source).foregroundStyle(.secondary)
            }
        case .code(let source, let count, let outputs):
            VStack(alignment: .leading, spacing: 8) {
                if !hidesCode, !source.isEmpty {
                    PromptRow(prompt: "In [\(count.map(String.init) ?? " ")]:") {
                        CodeBlockView(language: language, code: source)
                    }
                }
                ForEach(Array(outputs.enumerated()), id: \.offset) { index, output in
                    PromptRow(prompt: index == 0 && !hidesCode ? "Out:" : "") {
                        NotebookOutputView(output: output)
                    }
                }
            }
        case .raw(let source):
            if !hidesCode, !source.isEmpty {
                CodeBlockView(language: nil, code: source)
            }
        }
    }

    @concurrent
    private static func parseMarkdown(_ cells: [NotebookCellContent], notePath: String) async -> [Int: MarkdownDocument]
    {
        var result: [Int: MarkdownDocument] = [:]
        for cell in cells {
            if case .markdown(let source) = cell.kind {
                result[cell.id] = MarkdownDocumentParser.parse(source, notePath: notePath)
            }
        }
        return result
    }
}

/// 左に `In [3]:` のような印を置いた行。
private struct PromptRow<Content: View>: View {
    let prompt: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(prompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .trailing)
                .textSelection(.disabled)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 1 つの出力。
private struct NotebookOutputView: View {
    let output: NotebookOutputContent

    var body: some View {
        switch output {
        case .text(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: EditorTheme.codeSize, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .scrollIndicators(.automatic)
        case .image(let data):
            NotebookImageView(data: data)
        case .table(let rows, let truncated):
            NotebookTableView(rows: rows, truncated: truncated)
        case .error(let name, let message, let traceback):
            VStack(alignment: .leading, spacing: 6) {
                Text("\(name): \(message)").fontWeight(.semibold)
                if !traceback.isEmpty {
                    ScrollView(.horizontal) {
                        Text(traceback)
                            .font(.system(size: EditorTheme.codeSize - 1, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: .rect(cornerRadius: 6))
        }
    }
}

/// 出力の図。読み込みは裏で行い、元の大きさより大きくはしない。
private struct NotebookImageView: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width, alignment: .leading)
                    .contextMenu {
                        Button("画像をコピー", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([image])
                        }
                    }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: data) {
            let data = data
            image = await Task.detached { NSImage(data: data) }.value
        }
    }
}

/// 出力の表（pandas の DataFrame など）。
private struct NotebookTableView: View {
    let rows: [[String]]
    let truncated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value)
                                    .fontWeight(index == 0 ? .semibold : .regular)
                                    .lineLimit(1)
                            }
                        }
                        if index == 0 { Divider() }
                    }
                }
                .font(.system(size: EditorTheme.codeSize - 1, design: .monospaced))
                .padding(8)
            }
            .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 6))
            if truncated {
                Text("表が長いので、先頭 \(rows.count) 行だけを見せています")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
