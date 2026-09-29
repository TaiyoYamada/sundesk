//
//  RenderedPage.swift
//  SundeskRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Foundation
import Observation
import WebKit

/// Markdown、コード、HTML を描く WebKit のページ。SwiftUI の `WebView(page.webPage)` で表示する。
@MainActor
@Observable
public final class RenderedPage {
    public let webPage: WebPage
    /// 描いたノートの目次（見出し）。
    public private(set) var headings: [RenderedHeading] = []

    /// `[[リンク]]` や相対リンクが押されたときに呼ばれる。
    @ObservationIgnored public var onOpen: ((RendererURL.OpenRequest) -> Void)? {
        get { links.onOpen }
        set { links.onOpen = newValue }
    }

    @ObservationIgnored private let links: LinkHandler
    @ObservationIgnored private var isRendererLoaded = false

    public init(vaultRoot: @escaping @Sendable () -> URL) {
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(RendererURL.appScheme)!] = FileSchemeHandler(root: {
            RendererAssets.directory
        })
        configuration.urlSchemeHandlers[URLScheme(RendererURL.vaultScheme)!] = FileSchemeHandler(root: vaultRoot)
        let links = LinkHandler()
        self.links = links
        self.webPage = WebPage(configuration: configuration, navigationDecider: LinkDecider(handler: links))
        #if DEBUG
            webPage.isInspectable = true
        #endif
    }

    /// Markdown を描く。`path` は Vault のルートからのパス（相対リンクの基準）。
    public func showMarkdown(_ source: String, path: String) async throws {
        try await loadRenderer()
        let result = try await webPage.callJavaScript(
            "return await window.sundesk.renderMarkdown(source, path)",
            arguments: ["source": source, "path": path]
        )
        headings = RenderedHeading.list(from: result)
    }

    /// コードやテキストを、行番号と色づけつきで描く。
    public func showCode(_ source: String, language: String) async throws {
        try await loadRenderer()
        _ = try await webPage.callJavaScript(
            "return await window.sundesk.renderCode(source, language)",
            arguments: ["source": source, "language": language]
        )
        headings = []
    }

    /// Vault の中の HTML ファイルを、そのまま開く。
    public func showHTMLFile(path: String) async throws {
        isRendererLoaded = false
        headings = []
        for try await _ in webPage.load(RendererURL.vaultURL(for: path)) {}
    }

    public func scroll(to heading: RenderedHeading) {
        Task {
            _ = try? await webPage.callJavaScript("window.sundesk.scrollToHeading(id)", arguments: ["id": heading.id])
        }
    }

    private func loadRenderer() async throws {
        guard !isRendererLoaded else { return }
        for try await _ in webPage.load(RendererURL.indexURL) {}
        isRendererLoaded = true
    }
}

/// 描いたノートの見出し。
public struct RenderedHeading: Identifiable, Hashable, Sendable {
    public let id: String
    public let level: Int
    public let text: String

    public init(id: String, level: Int, text: String) {
        self.id = id
        self.level = level
        self.text = text
    }

    /// renderer が返す `{ headings: [{ id, level, text }] }` を読む。
    static func list(from result: Any?) -> [RenderedHeading] {
        guard let dictionary = result as? [String: Any], let items = dictionary["headings"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let text = item["text"] as? String else { return nil }
            let level = (item["level"] as? NSNumber)?.intValue ?? 1
            return RenderedHeading(id: id, level: level, text: text)
        }
    }
}

// MARK: - リンクの扱い

@MainActor
private final class LinkHandler {
    var onOpen: ((RendererURL.OpenRequest) -> Void)?
}

/// ページの中でのリンクの移動を判定する。
///
/// - `sundesk-open:` → 移動せず、アプリがタブで開く
/// - HTML のノートの中から、Vault の別のファイルへのリンク → 同じくアプリで開く
/// - `http:` など → 既定のブラウザで開く
/// - 同梱した renderer と、最初の読み込み → 許可する
private struct LinkDecider: WebPage.NavigationDeciding {
    let handler: LinkHandler

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let isClick = action.navigationType == .linkActivated

        switch url.scheme {
        case RendererURL.openScheme:
            if let request = RendererURL.openRequest(from: url) { handler.onOpen?(request) }
            return .cancel
        case RendererURL.appScheme, "about":
            return .allow
        case RendererURL.vaultScheme:
            if isClick, let path = RendererURL.vaultPath(from: url) {
                handler.onOpen?(RendererURL.OpenRequest(target: path, isExactPath: true))
                return .cancel
            }
            return .allow
        default:
            if isClick { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }
}
