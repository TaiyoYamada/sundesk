//
//  HTMLDocumentView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import OSLog
import SundeskWebView
import SwiftUI
import WebKit

/// Vault の中の HTML ファイルを WebKit で描く。
struct HTMLDocumentView: View {
    let page: HTMLPage
    let path: String
    let vaultRoot: URL
    /// 保存のたびに変わる。変わったら読み直す。
    let revision: Int
    let openFile: (String) -> Void

    private static let logger = Logger(subsystem: "com.taiyou.sundesk", category: "html")

    var body: some View {
        WebView(page.webPage)
            .task(id: revision) {
                page.vaultRoot = vaultRoot
                page.onOpen = openFile
                do {
                    try await page.show(path: path)
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.error(
                        "HTML を開けない: \(path, privacy: .public) \(error.localizedDescription, privacy: .public)")
                }
            }
            .accessibilityIdentifier("html-view")
    }
}
