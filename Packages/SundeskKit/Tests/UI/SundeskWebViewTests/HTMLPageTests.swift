//
//  HTMLPageTests.swift
//  SundeskWebViewTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Testing
import WebKit

@testable import SundeskWebView

@Suite("VaultURL")
struct VaultURLTests {
    @Test("Vault のパスと URL を行き来できる（日本語と空白を含む）")
    func roundTrip() {
        let path = "論文メモ/Attention Is All You Need.html"
        let url = VaultURL.url(for: path)

        #expect(url.scheme == "sundesk-vault")
        #expect(VaultURL.path(from: url) == path)
        #expect(VaultURL.path(from: URL(string: "https://example.com")!) == nil)
    }
}

/// テスト用の Vault（一時フォルダ）。
private struct TemporaryVault {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "sundesk-web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "資料"), withIntermediateDirectories: true)
        try Data("<h1 id=\"title\">見出し</h1>".utf8).write(to: root.appending(path: "資料/ページ.html"))
        try Data("h1 { color: red }".utf8).write(to: root.appending(path: "資料/style.css"))
    }
}

@Suite("FileSchemeHandler")
struct FileSchemeHandlerTests {
    @Test("フォルダの中のファイルを返す")
    func servesFileInside() throws {
        let vault = try TemporaryVault()
        let handler = FileSchemeHandler(root: { vault.root })

        #expect(handler.file(for: VaultURL.url(for: "資料/ページ.html")) != nil)
    }

    @Test("フォルダの外や、ないファイルは返さない", arguments: ["../../etc/hosts", "ない.css", ""])
    func rejectsOutside(path: String) throws {
        let vault = try TemporaryVault()
        let handler = FileSchemeHandler(root: { vault.root })

        #expect(handler.file(for: VaultURL.url(for: path)) == nil)
    }

    @Test("応答に MIME タイプと中身を入れる")
    func repliesWithMIMETypeAndData() async throws {
        let vault = try TemporaryVault()
        let handler = FileSchemeHandler(root: { vault.root })
        var results: [URLSchemeTaskResult] = []
        for try await result in handler.reply(for: URLRequest(url: VaultURL.url(for: "資料/style.css"))) {
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
@Suite("HTMLPage（本物の WebKit で描く）", .timeLimit(.minutes(1)))
struct HTMLPageTests {
    @Test("Vault の HTML ファイルを開く")
    func showsHTMLFile() async throws {
        let vault = try TemporaryVault()
        let page = HTMLPage()
        page.vaultRoot = vault.root

        try await page.show(path: "資料/ページ.html")

        let text = try await page.webPage.callJavaScript("return document.getElementById('title').textContent")
        #expect(text as? String == "見出し")
    }
}
