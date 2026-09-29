//
//  HTMLPage.swift
//  SundeskWebView
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Foundation
import Observation
import Synchronization
import WebKit

/// Vault の中の HTML ファイルを描く WebKit のページ。SwiftUI の `WebView(page.webPage)` で表示する。
///
/// ページは独自スキーム（`sundesk-vault:`）で読み、Vault の外のファイルには触れさせない。
@MainActor
@Observable
public final class HTMLPage {
    public let webPage: WebPage

    /// ページの中で、Vault の別のファイルへのリンクが押されたとき（Vault のルートからのパス）。
    @ObservationIgnored public var onOpen: ((String) -> Void)? {
        get { links.onOpen }
        set { links.onOpen = newValue }
    }

    /// Vault のフォルダ。ページから読む画像などの置き場所。
    public var vaultRoot: URL {
        get { root.url }
        set { root.url = newValue }
    }

    @ObservationIgnored private let links: LinkHandler
    @ObservationIgnored private let root = VaultRootBox()

    public init() {
        var configuration = WebPage.Configuration()
        let root = self.root
        configuration.urlSchemeHandlers[URLScheme(VaultURL.scheme)!] = FileSchemeHandler(root: { root.url })
        let links = LinkHandler()
        self.links = links
        self.webPage = WebPage(configuration: configuration, navigationDecider: LinkDecider(handler: links))
        #if DEBUG
            webPage.isInspectable = true
        #endif
    }

    /// Vault の中の HTML ファイルを開く（同じファイルでも読み直す）。
    public func show(path: String) async throws {
        for try await _ in webPage.load(VaultURL.url(for: path)) {}
    }
}

/// Vault のフォルダ。ページ（MainActor）と、ファイルを配る処理（別のスレッド）の両方から読む。
nonisolated private final class VaultRootBox: Sendable {
    private let storage = Mutex(URL(filePath: "/nonexistent"))

    var url: URL {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

// MARK: - リンクの扱い

@MainActor
private final class LinkHandler {
    var onOpen: ((String) -> Void)?
}

/// ページの中でのリンクの移動を判定する。
///
/// - Vault の別のファイルへのリンク → 移動せず、アプリがタブで開く
/// - `http:` など → 既定のブラウザで開く
/// - 最初の読み込みと、ページが読む画像など → 許可する
private struct LinkDecider: WebPage.NavigationDeciding {
    let handler: LinkHandler

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let isClick = action.navigationType == .linkActivated

        switch url.scheme {
        case VaultURL.scheme:
            if isClick, let path = VaultURL.path(from: url) {
                handler.onOpen?(path)
                return .cancel
            }
            return .allow
        case "about":
            return .allow
        default:
            if isClick { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }
}
