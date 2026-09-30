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

        let document = try await OpenDocumentInteractor(vault: vault, markdown: MarkdownParserStub())(path: "ノート.md")

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
        let open = OpenDocumentInteractor(vault: vault, markdown: MarkdownParserStub())

        #expect(try await open(path: "図.png").content == .image(vault.fileURL(for: "図.png")))
        #expect(try await open(path: "資料.pdf").content == .pdf(vault.fileURL(for: "資料.pdf")))
        #expect(await vault.readCount == 0)
    }

    @Test("ないファイルは fileNotFound")
    func missingFileThrows() async {
        await #expect(throws: VaultError.fileNotFound(path: "ない.md")) {
            try await OpenDocumentInteractor(vault: VaultStub(files: [:]), markdown: MarkdownParserStub())(
                path: "ない.md")
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

        let summary = try await IndexVaultInteractor(vault: vault, index: index, markdown: MarkdownParserStub())()

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
        let indexVault = IndexVaultInteractor(vault: vault, index: index, markdown: MarkdownParserStub())
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
        let indexVault = IndexVaultInteractor(vault: vault, index: index, markdown: MarkdownParserStub())
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
        let indexVault = IndexVaultInteractor(vault: vault, index: index, markdown: MarkdownParserStub())
        _ = try await indexVault()

        _ = try await indexVault()

        #expect(await index.applyCount == 1)
    }
}

@Suite("保存と、ファイルの場所")
struct SaveAndLocateTests {
    @Test("保存すると Vault に書き込む")
    func savesText() async throws {
        let vault = VaultStub(files: ["a.md": "古い"])

        try await SaveDocumentInteractor(vault: vault)("新しい", to: "a.md")

        #expect(await vault.content(of: "a.md") == "新しい")
    }

    @Test("パスをファイルの場所にする")
    func locatesFile() {
        let locate = LocateFileInteractor(vault: VaultStub(files: [:]))

        #expect(locate("数学/ベクトル.md") == URL(filePath: "/vault/数学/ベクトル.md"))
        #expect(locate.vaultRoot() == URL(filePath: "/vault"))
    }
}

@Suite("Vault を同期する")
struct SyncVaultTests {
    @Test("木を返し、索引も作る")
    func returnsTreeAndIndexes() async throws {
        let vault = VaultStub(files: ["a.md": "# A"])
        let index = NoteIndexSpy()
        let sync = SyncVaultInteractor(
            vault: vault,
            indexVault: IndexVaultInteractor(vault: vault, index: index, markdown: MarkdownParserStub())
        )

        let tree = try await sync()

        #expect(tree.files.map(\.path) == ["a.md"])
        #expect(await index.notes["a.md"]?.title == "A")
    }
}

@Suite("設定")
struct SettingsTests {
    private let defaults = SettingsDefaults(
        vaultDirectory: "/既定/vault", engineDirectory: "/既定/engine", uvExecutable: "/既定/uv")

    @Test("空欄は既定値で埋める")
    func resolvesDefaults() {
        let resolved = AppSettings(vaultDirectory: "", engineDirectory: "/自分/engine").resolved(with: defaults)

        #expect(resolved.vaultDirectory == "/既定/vault")
        #expect(resolved.engineDirectory == "/自分/engine")
        #expect(resolved.uvExecutable == "/既定/uv")
    }

    @Test("変えた項目だけを保存し、ほかは残す")
    func updateKeepsOtherFields() {
        let repository = SettingsRepositoryStub(
            settings: AppSettings(vaultDirectory: "/a", engineDirectory: "/b"), defaults: defaults)

        UpdateSettingsInteractor(repository: repository)({ $0.vaultDirectory = "/c" })

        #expect(repository.load() == AppSettings(vaultDirectory: "/c", engineDirectory: "/b"))
        #expect(LoadSettingsInteractor(repository: repository).defaults == defaults)
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

/// Markdown の解析の偽物。`# 見出し` をタイトルに、`[[リンク]]` をリンクに、
/// フロントマターの `tags: [a, b]` をタグにする（Domain のテストは Infrastructure に依存しない）。
struct MarkdownParserStub: MarkdownParsing {
    func analyze(_ source: String, path: String) -> NoteAnalysis {
        let title = source.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
        let links = source.matches(of: /\[\[([^\]]+)\]\]/).map {
            NoteLinkReference(target: String($0.output.1), isExactPath: false)
        }
        let tags =
            source.firstMatch(of: /tags: \[([^\]]*)\]/).map {
                $0.output.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } ?? []
        return NoteAnalysis(title: title, properties: [], tags: tags, links: links, body: source)
    }
}

final class SettingsRepositoryStub: SettingsRepository, @unchecked Sendable {
    private var settings: AppSettings
    let defaults: SettingsDefaults

    init(settings: AppSettings, defaults: SettingsDefaults) {
        self.settings = settings
        self.defaults = defaults
    }

    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
}

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

    func writeText(_ text: String, to path: String) async throws(VaultError) {
        touch(path, content: text)
    }

    func content(of path: String) -> String? {
        files[path]
    }

    nonisolated func rootURL() -> URL {
        URL(filePath: "/vault")
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

    func stamps() async throws(NoteIndexError) -> [String: String] {
        notes.mapValues(\.stamp)
    }

    func pathSignature() async throws(NoteIndexError) -> String? {
        signature
    }

    func apply(_ changes: NoteIndexChanges) async throws(NoteIndexError) {
        applyCount += 1
        for note in changes.upserts { notes[note.path] = note }
        for path in changes.removals { notes[path] = nil }
        signature = changes.pathSignature
    }

    func backlinks(to path: String) async throws(NoteIndexError) -> [NoteSummary] {
        notes.values.filter { $0.linkedPaths.contains(path) }.map { NoteSummary(path: $0.path, title: $0.title) }
    }

    func search(_ query: String, limit: Int) async throws(NoteIndexError) -> [SearchResult] {
        searchCount += 1
        return []
    }

    func tags() async throws(NoteIndexError) -> [TagCount] { [] }

    func notes(taggedWith tag: String) async throws(NoteIndexError) -> [NoteSummary] { [] }

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
