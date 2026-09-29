//
//  WebDocumentView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import OSLog
import SundeskDomain
import SundeskPresentation
import SundeskRenderer
import SwiftUI
import WebKit

/// Markdown、HTML、テキスト、コードを WebKit で描く。
struct WebDocumentView: View {
    let document: DocumentViewModel
    let loaded: SundeskDomain.Document
    let workspace: WorkspaceViewModel
    let page: RenderedPage

    private static let logger = Logger(subsystem: "com.taiyou.sundesk", category: "renderer")

    var body: some View {
        WebView(page.webPage)
            .task(id: RenderRequest(document: loaded, mode: document.displayMode)) { await render() }
            .onAppear {
                page.onOpen = { request in
                    Task { await workspace.openLink(request.target, isExactPath: request.isExactPath) }
                }
            }
    }

    private func render() async {
        do {
            switch (loaded.content, document.displayMode) {
            case (.markdown(let source, _), .rendered):
                try await page.showMarkdown(source, path: loaded.path)
            case (.html, .rendered):
                try await page.showHTMLFile(path: loaded.path)
            case (let content, _):
                try await page.showCode(content.source ?? "", language: loaded.kind.sourceLanguage ?? "text")
            }
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("描画に失敗: \(loaded.path, privacy: .public) \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 中身か表示の形が変わったときだけ描き直す。
    private struct RenderRequest: Equatable {
        let document: SundeskDomain.Document
        let mode: DocumentViewModel.DisplayMode
    }
}
