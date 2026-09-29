//
//  FileSystemVaultRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import Testing

@Suite("FileSystemVaultRepository")
struct FileSystemVaultRepositoryTests {
    @Test("フォルダを木にする。隠しファイルと node_modules は含めない")
    func loadsTree() async throws {
        let vault = try TemporaryVault(files: [
            "ホーム.md": "# ホーム",
            "量子計算/量子ビット.md": "# 量子ビット",
            "資料/図.png": "",
            ".obsidian/app.json": "{}",
            "node_modules/x.js": "",
        ])
        defer { vault.remove() }

        let tree = try await vault.repository.loadTree()

        #expect(Set(tree.files.map(\.path)) == ["ホーム.md", "量子計算/量子ビット.md", "資料/図.png"])
        #expect(tree.node(at: "量子計算")?.kind == .folder)
        #expect(tree.node(at: "資料/図.png")?.kind == .image)
    }

    @Test("テキストを読み、ファイルの情報を返す")
    func readsTextAndInfo() async throws {
        let vault = try TemporaryVault(files: ["a.md": "こんにちは"])
        defer { vault.remove() }

        #expect(try await vault.repository.readText(at: "a.md") == "こんにちは")
        let info = try await vault.repository.fileInfo(at: "a.md")
        #expect(info.size == "こんにちは".utf8.count)
    }

    @Test("Shift_JIS のテキストも読める")
    func readsShiftJIS() async throws {
        let vault = try TemporaryVault(files: [:])
        defer { vault.remove() }
        try #require("日本語のメモ".data(using: .shiftJIS)).write(to: vault.url.appending(path: "sjis.txt"))

        #expect(try await vault.repository.readText(at: "sjis.txt") == "日本語のメモ")
    }

    @Test("Vault の外や、存在しないファイルは読めない", arguments: ["../外.md", "ない.md", ""])
    func rejectsOutsideAndMissing(path: String) async throws {
        let vault = try TemporaryVault(files: ["a.md": ""])
        defer { vault.remove() }

        await #expect(throws: VaultError.fileNotFound(path: path)) {
            try await vault.repository.readText(at: path)
        }
    }

    @Test("Vault のフォルダがなければ vaultNotFound")
    func missingVault() async {
        let repository = FileSystemVaultRepository(root: { URL(filePath: "/nonexistent/vault") })
        await #expect(throws: VaultError.vaultNotFound(path: "/nonexistent/vault")) {
            try await repository.loadTree()
        }
    }

    @Test("ファイルが変わると changes に流れる", .timeLimit(.minutes(1)))
    func notifiesChanges() async throws {
        let vault = try TemporaryVault(files: [:])
        defer { vault.remove() }
        var changes = vault.repository.changes().makeAsyncIterator()
        try await Task.sleep(for: .milliseconds(300))  // 監視が始まるのを待つ

        try "# 新しいノート".write(to: vault.url.appending(path: "new.md"), atomically: true, encoding: .utf8)

        #expect(await changes.next() != nil)
    }
}

/// テストのたびに作って消す Vault。
struct TemporaryVault {
    let url: URL
    let repository: FileSystemVaultRepository

    init(files: [String: String]) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sundesk-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        for (path, content) in files {
            let file = url.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.url = url
        self.repository = FileSystemVaultRepository(root: { url })
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
