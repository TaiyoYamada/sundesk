//
//  MarkdownReadingView.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskMarkdown
import SwiftUI

/// ノートを整形して読むための表示（閲覧モード）。swift-markdown で解析し、SwiftUI で描く。
public struct MarkdownReadingView: View {
    private let source: String
    private let notePath: String
    private let vaultRoot: URL
    @Binding private var scrollToHeading: Int?
    private let onOpen: (DocumentLink) -> Void
    @State private var document: MarkdownDocument?

    /// - Parameters:
    ///   - notePath: Vault のルートからのパス（相対リンクと画像の基準）。
    ///   - vaultRoot: Vault のフォルダ（ノートの中の画像を読む）。
    ///   - scrollToHeading: 何番目の見出しへスクロールするか。スクロールしたら nil に戻す。
    ///   - onOpen: リンクが押されたとき（同じノートの見出しへのリンクは、この中でスクロールする）。
    public init(
        source: String,
        notePath: String,
        vaultRoot: URL,
        scrollToHeading: Binding<Int?>,
        onOpen: @escaping (DocumentLink) -> Void
    ) {
        self.source = source
        self.notePath = notePath
        self.vaultRoot = vaultRoot
        self._scrollToHeading = scrollToHeading
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let document {
                    BlocksView(blocks: document.blocks, spacing: 14)
                        .environment(\.readingContext, ReadingContext(vaultRoot: vaultRoot))
                        .textSelection(.enabled)
                        .frame(maxWidth: EditorTheme.readableWidth, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                }
            }
            .environment(
                \.openURL,
                OpenURLAction { url in
                    let link = DocumentLink(url: url)
                    if case .heading(let anchor) = link, let document,
                        let index = document.headings.first(where: { HeadingAnchor.matches(anchor, heading: $0.text) })?
                            .index
                    {
                        withAnimation { proxy.scrollTo(HeadingID(index: index), anchor: .top) }
                    } else {
                        onOpen(link)
                    }
                    return .handled
                }
            )
            .onChange(of: scrollToHeading) { _, index in
                guard let index else { return }
                withAnimation { proxy.scrollTo(HeadingID(index: index), anchor: .top) }
                scrollToHeading = nil
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: source) { document = await Self.parse(source, notePath: notePath) }
        .accessibilityIdentifier("reading-view")
    }

    @concurrent
    private static func parse(_ source: String, notePath: String) async -> MarkdownDocument {
        MarkdownDocumentParser.parse(source, notePath: notePath)
    }
}

/// 見出しへスクロールするときの目印。
struct HeadingID: Hashable {
    let index: Int
}

/// 描くのに必要な周りの情報。
struct ReadingContext {
    var vaultRoot = URL(filePath: "/")
}

extension EnvironmentValues {
    @Entry var readingContext = ReadingContext()
}

extension MarkdownDocument {
    /// すべての見出し（引用や注記の中のものも含む）。
    var headings: [(index: Int, text: String)] {
        func collect(_ blocks: [MarkdownBlock]) -> [(index: Int, text: String)] {
            blocks.flatMap { block -> [(index: Int, text: String)] in
                switch block {
                case .heading(_, let content, let index): [(index, content.map(\.plainText).joined())]
                case .quote(let children), .callout(_, _, let children): collect(children)
                case .list(_, _, let items): items.flatMap { collect($0.blocks) }
                default: []
                }
            }
        }
        return collect(blocks)
    }
}
