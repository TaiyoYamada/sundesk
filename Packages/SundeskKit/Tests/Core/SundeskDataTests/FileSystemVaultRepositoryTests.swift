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

    @Test("書き込むと、読み直したときに新しい内容になる。フォルダがなければ作る")
    func writesText() async throws {
        let vault = try TemporaryVault(files: ["a.md": "古い"])
        defer { vault.remove() }

        try await vault.repository.writeText("新しい", to: "a.md")
        try await vault.repository.writeText("# 新規", to: "新しいフォルダ/b.md")

        #expect(try await vault.repository.readText(at: "a.md") == "新しい")
        #expect(try await vault.repository.readText(at: "新しいフォルダ/b.md") == "# 新規")
    }

    @Test("Vault の外には書き込めない")
    func rejectsWritingOutside() async throws {
        let vault = try TemporaryVault(files: [:])
        defer { vault.remove() }

        await #expect(throws: VaultError.fileNotFound(path: "../外.md")) {
            try await vault.repository.writeText("x", to: "../外.md")
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

@Suite("読むだけでつなぐフォルダ")
struct VaultMountTests {
    @Test("つないだフォルダは一番上に現れ、読めるが書き込めない")
    func mountsAreReadOnly() async throws {
        let library = try TemporaryVault(files: ["Notes/自分.md": "# 自分"])
        let research = try TemporaryVault(files: [
            "paper/a.pdf": "", "experiment/demo/README.md": "# デモ", "experiment/demo/.venv/x.py": "",
        ])
        defer {
            library.remove()
            research.remove()
        }
        let mount = VaultMount(name: "Research", url: research.url)
        let repository = FileSystemVaultRepository(root: { library.url }, mounts: { [mount] })

        let tree = try await repository.loadTree()

        #expect(
            Set(tree.files.map(\.path))
                == ["Notes/自分.md", "Research/paper/a.pdf", "Research/experiment/demo/README.md"])
        #expect(try await repository.readText(at: "Research/experiment/demo/README.md") == "# デモ")
        #expect(repository.isReadOnly("Research/experiment/demo/README.md"))
        #expect(!repository.isReadOnly("Notes/自分.md"))
        let pdf = repository.fileURL(for: "Research/paper/a.pdf")
        #expect(pdf.path == research.url.appending(path: "paper/a.pdf").path)
        await #expect(throws: VaultError.readOnly(path: "Research/x.md")) {
            try await repository.writeText("x", to: "Research/x.md")
        }
        await #expect(throws: VaultError.fileNotFound(path: "Research/../../外.md")) {
            try await repository.readText(at: "Research/../../外.md")
        }
    }

    @Test("study-artifact は選んだフォルダと、研究のタグの付いた _inbox のノートだけを見せる")
    func filtersStudySections() async throws {
        let library = try TemporaryVault(files: [:])
        let study = try TemporaryVault(files: [
            "notes/02-最適化/ABC.md": "# デモ",
            "notes/12-ソフトウェア開発/Swift.md": "# Swift",
            "notes/_inbox/焼きなまし.md": "---\ntitle: 焼きなまし\ntags: [最適化, SA]\n---\n# 焼きなまし",
            "notes/_inbox/SvelteKit.md": "---\ntags: [sveltekit]\n---\n# SvelteKit",
        ])
        defer {
            library.remove()
            study.remove()
        }
        let mounts = ResearchSources.mounts(
            research: "", study: study.url.path, studySections: ["02-最適化"]
        ) { FileManager.default.fileExists(atPath: $0) }
        let repository = FileSystemVaultRepository(root: { library.url }, mounts: { mounts })

        let tree = try await repository.loadTree()

        #expect(
            Set(tree.files.map(\.path)) == ["study-artifact/02-最適化/ABC.md", "study-artifact/_inbox/焼きなまし.md"])
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
