//
//  DocumentView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskEditorUI
import SwiftUI

/// 開いたファイルを描く。どう描くかは ViewModel（`display`）が決める。
public struct DocumentView: View {
    @Bindable private var document: DocumentViewModel
    private let cache: DocumentViewCache
    private let openLink: (String, Bool) -> Void
    private let showTag: (String) -> Void

    /// - Parameters:
    ///   - openLink: ノートの中のリンクが押されたときに呼ぶ（リンク先、正確なパスかどうか）。
    ///   - showTag: タグが押されたときに呼ぶ。
    public init(
        document: DocumentViewModel,
        cache: DocumentViewCache,
        openLink: @escaping (String, Bool) -> Void,
        showTag: @escaping (String) -> Void
    ) {
        self.document = document
        self.cache = cache
        self.openLink = openLink
        self.showTag = showTag
    }

    public var body: some View {
        VStack(spacing: 0) {
            if case .failed(let message) = document.saveState {
                SaveErrorBanner(message: message) {
                    Task { await document.flush() }
                }
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: document.path) { await document.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch document.display {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("開けませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .markdownEditor(let livePreview):
            TextEditorView(
                session: cache.editor(for: document.path),
                text: $document.text,
                syntax: .markdown(livePreview: livePreview, notePath: document.path),
                scrollToLine: scrollToLine,
                isEditable: document.isEditable,
                onOpen: open
            )
        case .markdownReading(let vaultRoot):
            MarkdownReadingView(
                source: document.text,
                notePath: document.path,
                vaultRoot: vaultRoot,
                scrollToHeading: scrollToHeading,
                onOpen: open
            )
        case .htmlPage(let vaultRoot):
            HTMLDocumentView(
                page: cache.page(for: document.path),
                path: document.path,
                vaultRoot: vaultRoot,
                revision: document.revision,
                openFile: { openLink($0, true) }
            )
        case .codeEditor(let language):
            TextEditorView(
                session: cache.editor(for: document.path),
                text: $document.text,
                syntax: language.map { .code(language: $0) } ?? .plain,
                scrollToLine: .constant(nil),
                isEditable: document.isEditable,
                onOpen: open
            )
        case .image(let url):
            ImageDocumentView(url: url)
        case .pdf(let url):
            PDFDocumentView(url: url)
        case .quickLook(let url):
            QuickLookView(url: url)
        }
    }

    /// 目次で選んだ見出しの行（エディタ）。
    private var scrollToLine: Binding<Int?> {
        Binding(
            get: { document.scrollTarget?.line },
            set: { if $0 == nil { document.scrollTarget = nil } }
        )
    }

    /// 目次で選んだ見出しの番号（閲覧）。
    private var scrollToHeading: Binding<Int?> {
        Binding(
            get: { document.scrollTarget?.index },
            set: { if $0 == nil { document.scrollTarget = nil } }
        )
    }

    private func open(_ link: DocumentLink) {
        switch link {
        case .note(let target):
            openLink(target, false)
        case .file(let path):
            openLink(path, true)
        case .external(let url):
            NSWorkspace.shared.open(url)
        case .heading(let anchor):
            document.scrollTarget = document.outline.first { HeadingAnchor.matches(anchor, heading: $0.title) }
        case .tag(let name):
            showTag(name)
        }
    }
}

/// 保存に失敗したときに、エディタの上に出す帯。
private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
            Spacer()
            Button("もう一度保存", action: retry)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.1))
    }
}
