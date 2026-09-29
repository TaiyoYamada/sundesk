//
//  RendererTests.swift
//  SundeskRendererTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Testing
import WebKit

@testable import SundeskRenderer

@Suite("RendererURL")
struct RendererURLTests {
    @Test("Vault のパスと URL を行き来できる（日本語と空白を含む）")
    func vaultURLRoundTrip() {
        let path = "論文メモ/Attention Is All You Need.md"
        let url = RendererURL.vaultURL(for: path)

        #expect(url.scheme == "sundesk-vault")
        #expect(RendererURL.vaultPath(from: url) == path)
    }

    @Test("ノートを開く指示を読む")
    func parsesOpenRequest() throws {
        let url = try #require(
            URL(string: "sundesk-open://note?target=%E9%87%8F%E5%AD%90%E3%82%B2%E3%83%BC%E3%83%88&exact=1"))
        #expect(RendererURL.openRequest(from: url) == .init(target: "量子ゲート", isExactPath: true))
        #expect(RendererURL.openRequest(from: URL(string: "sundesk-open://note?target=")!) == nil)
        #expect(RendererURL.openRequest(from: URL(string: "https://example.com")!) == nil)
    }

    @Test("同梱した renderer がそろっている")
    func assetsExist() {
        for name in ["index.html", "renderer.js", "renderer.css"] {
            #expect(
                FileManager.default.fileExists(atPath: RendererAssets.directory.appending(path: name).path),
                "\(name) がない")
        }
    }
}

@Suite("FileSchemeHandler")
struct FileSchemeHandlerTests {
    private let handler = FileSchemeHandler(root: { RendererAssets.directory })

    @Test("フォルダの中のファイルを返す")
    func servesFileInside() {
        #expect(handler.file(for: URL(string: "sundesk-app://renderer/index.html")!) != nil)
    }

    @Test("フォルダの外や、ないファイルは返さない", arguments: ["/../../Package.swift", "/ない.js", "/"])
    func rejectsOutside(path: String) {
        var components = URLComponents()
        components.scheme = "sundesk-app"
        components.host = "renderer"
        components.path = path
        #expect(handler.file(for: components.url!) == nil)
    }

    @Test("応答に MIME タイプと中身を入れる")
    func repliesWithMIMETypeAndData() async throws {
        var results: [URLSchemeTaskResult] = []
        for try await result in handler.reply(for: URLRequest(url: URL(string: "sundesk-app://renderer/renderer.css")!))
        {
            results.append(result)
        }

        guard case .response(let response) = results.first, case .data(let data) = results.last else {
            Issue.record("応答の形が違う: \(results)")
            return
        }
        #expect(response.mimeType == "text/css")
        #expect(!data.isEmpty)
    }
}

@MainActor
@Suite("RenderedPage（本物の WebKit で描く）", .timeLimit(.minutes(1)))
struct RenderedPageTests {
    @Test("Markdown を描き、目次を受け取る")
    func rendersMarkdownAndReturnsHeadings() async throws {
        let page = RenderedPage(vaultRoot: { URL(filePath: "/tmp") })

        try await page.showMarkdown("# タイトル\n\n## 数式 $x^2$\n\n[[リンク]]", path: "a.md")

        #expect(page.headings.map(\.text) == ["タイトル", "数式"])
        #expect(page.headings.map(\.level) == [1, 2])
        let html =
            try await page.webPage.callJavaScript("return document.getElementById('content').innerHTML") as? String
        #expect(html?.contains("katex") == true)
        #expect(html?.contains("wikilink") == true)
    }

    @Test("コードを色づけして描く")
    func rendersCode() async throws {
        let page = RenderedPage(vaultRoot: { URL(filePath: "/tmp") })

        try await page.showCode("let x = 1", language: "swift")

        let html =
            try await page.webPage.callJavaScript("return document.getElementById('content').innerHTML") as? String
        #expect(html?.contains("shiki") == true)
        #expect(page.headings.isEmpty)
    }
}
