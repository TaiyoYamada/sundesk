//
//  DocumentView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import SundeskPresentation
import SwiftUI

/// 開いたファイルを、種類に合わせて表示する。
struct DocumentView: View {
    let document: DocumentViewModel
    let workspace: WorkspaceViewModel
    let pages: RenderedPageCache
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let message = document.errorMessage {
                ContentUnavailableView {
                    Label("開けませんでした", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            } else if let loaded = document.document {
                switch loaded.content {
                case .markdown, .html, .text:
                    WebDocumentView(
                        document: document, loaded: loaded, workspace: workspace, page: pages.page(for: document.path))
                case .image(let url):
                    ImageDocumentView(url: url)
                case .pdf(let url):
                    PDFDocumentView(url: url)
                case .other(let url):
                    QuickLookView(url: url)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: document.path) { await document.load() }
    }
}
