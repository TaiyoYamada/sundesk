//
//  VaultUseCaseTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import Testing

@Suite("ファイルを開く")
struct OpenDocumentTests {
    @Test("Markdown は本文と解析結果を返す")
    func opensMarkdown() async throws {
        let vault = VaultStub(files: ["ノート.md": "# タイトル\n[[リンク]]"])

        let document = try await OpenDocumentInteractor(vault: vault)(path: "ノート.md")

        #expect(document.kind == .markdown)
        #expect(document.title == "タイトル")
        guard case .markdown(let source, let analysis) = document.content else {
            Issue.record("Markdown ではない: \(document.content)")
            return
        }
        #expect(source == "# タイトル\n[[リンク]]")
        #expect(analysis.links.map(\.target) == ["リンク"])
    }

    @Test("画像と PDF は中身を読まずに場所だけを返す")
    func opensBinaryFilesByURL() async throws {
        let vault = VaultStub(files: ["図.png": "", "資料.pdf": ""])
        let open = OpenDocumentInteractor(vault: vault)

        #expect(try await open(path: "図.png").content == .image(vault.fileURL(for: "図.png")))
        #expect(try await open(path: "資料.pdf").content == .pdf(vault.fileURL(for: "資料.pdf")))
        #expect(await vault.readCount == 0)
    }

    @Test("ないファイルは fileNotFound")
    func missingFileThrows() async {
        await #expect(throws: VaultError.fileNotFound(path: "ない.md")) {
            try await OpenDocumentInteractor(vault: VaultStub(files: [:]))(path: "ない.md")
        }
    }

    @Test("リンク先を Vault の中から探す")
    func resolvesLink() async throws {
        let vault = VaultStub(files: ["数学/ベクトル.md": "", "ホーム.md": ""])
        let resolve = ResolveLinkInteractor(vault: vault)

        #expect(try await resolve("ベクトル", exact: false) == "数学/ベクトル.md")
        #expect(try await resolve("ない", exact: false) == nil)
    }
}

@Suite("索引を作る")
struct IndexVaultTests {
    @Test("初回はすべてのノートを索引に入れ、リンク先を解決する")
    func indexesAllNotesFirstTime() async throws {
        let vault = VaultStub(files: [
            "a.md": "---\ntags: [x]\n---\n# A\n[[b]] [[ない]] [[a]]",
            "b.md": "# B",
            "図.png": "",
        ])
        let index = NoteIndexSpy()

        let summary = try await IndexVaultInteractor(vault: vault, index: index)()

        #expect(summary == IndexSummary(total: 2, updated: 2, removed: 0))
        let noteA = try #require(await index.notes["a.md"])
        #expect(noteA.title == "A")
        #expect(noteA.tags == ["x"])
        #expect(noteA.linkedPaths == ["b.md"])  // 存在しないリンクと自分へのリンクは除く
        #expect(await index.notes["b.md"]?.title == "B")
    }

    @Test("変わっていないノートは読み直さない")
    func skipsUnchangedNotes() async throws {
        let vault = VaultStub(files: ["a.md": "# A", "b.md": "# B"])
        let index = NoteIndexSpy()
        let indexVault = IndexVaultInteractor(vault: vault, index: index)
        _ = try await indexVault()

        await vault.touch("b.md", content: "# B2")
        let summary = try await indexVault()

        #expect(summary.updated == 1)
        #expect(await index.notes["b.md"]?.title == "B2")
    }

    @Test("消えたノートを索引から外し、ファイルの増減があればすべて解決し直す")
    func removesDeletedNotesAndRelinks() async throws {
        let vault = VaultStub(files: ["a.md": "[[c]]", "b.md": "# B"])
        let index = NoteIndexSpy()
        let indexVault = IndexVaultInteractor(vault: vault, index: index)
        _ = try await indexVault()
        #expect(await index.notes["a.md"]?.linkedPaths == [])

        await vault.remove("b.md")
        await vault.touch("c.md", content: "# C")
        let summary = try await indexVault()

        #expect(summary == IndexSummary(total: 2, updated: 2, removed: 1))
        #expect(await index.notes["b.md"] == nil)
        #expect(await index.notes["a.md"]?.linkedPaths == ["c.md"])
    }

    @Test("何も変わっていなければ索引に書き込まない")
    func doesNotWriteWhenNothingChanged() async throws {
        let vault = VaultStub(files: ["a.md": "# A"])
        let index = NoteIndexSpy()
        let indexVault = IndexVaultInteractor(vault: vault, index: index)
        _ = try await indexVault()

        _ = try await indexVault()

        #expect(await index.applyCount == 1)
    }
}

@Suite("索引を引く")
struct NoteIndexQueryTests {
    @Test("空白だけの検索語では検索しない")
    func blankQueryReturnsNothing() async throws {
        let index = NoteIndexSpy()
        #expect(try await SearchNotesInteractor(index: index)("  ").isEmpty)
        #expect(await index.searchCount == 0)
    }
}

// MARK: - テスト用の偽物

actor VaultStub: VaultRepository {
    private var files: [String: String]
    private var modified: [String: Date] = [:]
    private(set) var readCount = 0
    private var clock = Date(timeIntervalSince1970: 1_000)

    init(files: [String: String]) {
        self.files = files
        for path in files.keys { modified[path] = clock }
    }

    func touch(_ path: String, content: String) {
        clock = clock.addingTimeInterval(10)
        files[path] = content
        modified[path] = clock
    }

    func remove(_ path: String) {
        files[path] = nil
        modified[path] = nil
    }

    func loadTree() async throws(VaultError) -> VaultNode {
        let nodes = files.keys.map { path in
            VaultNode(
                id: path, name: path.split(separator: "/").last.map(String.init) ?? path, kind: FileKind(fileName: path)
            )
        }
        return VaultNode(id: "", name: "Vault", kind: .folder, children: nodes)
    }

    func readText(at path: String) async throws(VaultError) -> String {
        readCount += 1
        guard let text = files[path] else { throw .fileNotFound(path: path) }
        return text
    }

    func fileInfo(at path: String) async throws(VaultError) -> FileInfo {
        guard let text = files[path], let date = modified[path] else { throw .fileNotFound(path: path) }
        return FileInfo(path: path, size: text.utf8.count, created: nil, modified: date)
    }

    nonisolated func fileURL(for path: String) -> URL {
        URL(filePath: "/vault").appending(path: path)
    }

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

actor NoteIndexSpy: NoteIndexRepository {
    private(set) var notes: [String: IndexedNote] = [:]
    private(set) var signature: String?
    private(set) var applyCount = 0
    private(set) var searchCount = 0

    func stamps() async throws -> [String: String] {
        notes.mapValues(\.stamp)
    }

    func pathSignature() async throws -> String? {
        signature
    }

    func apply(_ changes: NoteIndexChanges) async throws {
        applyCount += 1
        for note in changes.upserts { notes[note.path] = note }
        for path in changes.removals { notes[path] = nil }
        signature = changes.pathSignature
    }

    func backlinks(to path: String) async throws -> [NoteSummary] {
        notes.values.filter { $0.linkedPaths.contains(path) }.map { NoteSummary(path: $0.path, title: $0.title) }
    }

    func search(_ query: String, limit: Int) async throws -> [SearchResult] {
        searchCount += 1
        return []
    }

    func tags() async throws -> [TagCount] { [] }

    func notes(taggedWith tag: String) async throws -> [NoteSummary] { [] }

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
