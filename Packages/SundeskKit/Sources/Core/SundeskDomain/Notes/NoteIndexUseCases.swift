//
//  NoteIndexUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - 索引を作る

public struct IndexSummary: Sendable, Equatable {
    public let total: Int
    public let updated: Int
    public let removed: Int

    public init(total: Int, updated: Int, removed: Int) {
        self.total = total
        self.updated = updated
        self.removed = removed
    }
}

public enum IndexVaultError: Error, Sendable, Equatable {
    case vault(VaultError)
    case index(NoteIndexError)
}

public protocol IndexVaultUseCase: Sendable {
    func callAsFunction() async throws(IndexVaultError) -> IndexSummary
}

/// Vault の Markdown を読み、索引（タイトル、タグ、リンク、本文）を最新にする。
///
/// 前回から変わったノートだけを読み直す。ただし、ファイルが増えたり消えたりしたときは、
/// 他のノートのリンク先も変わりうるので、すべて読み直してリンクを解決し直す。
public struct IndexVaultInteractor: IndexVaultUseCase {
    private let vault: any VaultRepository
    private let index: any NoteIndexRepository
    private let markdown: any MarkdownParsing

    public init(vault: any VaultRepository, index: any NoteIndexRepository, markdown: any MarkdownParsing) {
        self.vault = vault
        self.index = index
        self.markdown = markdown
    }

    public func callAsFunction() async throws(IndexVaultError) -> IndexSummary {
        do {
            return try await rebuildIndex(tree: try await vault.loadTree())
        } catch let error as VaultError {
            throw .vault(error)
        } catch let error as NoteIndexError {
            throw .index(error)
        } catch {
            throw .index(.storage(String(describing: error)))
        }
    }

    private func rebuildIndex(tree: VaultNode) async throws -> IndexSummary {
        let allPaths = tree.files.map(\.path)
        let notes = tree.files.filter { $0.kind == .markdown }
        let signature = Self.signature(of: allPaths)

        let previousStamps = try await index.stamps()
        let pathsChanged = try await index.pathSignature() != signature
        let resolver = LinkResolver(paths: allPaths)

        var upserts: [IndexedNote] = []
        for note in notes {
            let info = try await vault.fileInfo(at: note.path)
            let stamp = "\(info.modified.timeIntervalSince1970)-\(info.size)"
            guard pathsChanged || previousStamps[note.path] != stamp else { continue }

            let source = try await vault.readText(at: note.path)
            let analysis = markdown.analyze(source, path: note.path)
            var seen = Set<String>()
            let linkedPaths = analysis.links
                .compactMap(resolver.resolve)
                .filter { $0 != note.path && seen.insert($0).inserted }
            upserts.append(
                IndexedNote(
                    path: note.path,
                    title: analysis.title ?? note.stem,
                    tags: analysis.tags,
                    linkedPaths: linkedPaths,
                    body: analysis.body,
                    stamp: stamp
                )
            )
        }

        let removals = Set(previousStamps.keys).subtracting(notes.map(\.path)).sorted()
        if !upserts.isEmpty || !removals.isEmpty || pathsChanged {
            try await index.apply(NoteIndexChanges(upserts: upserts, removals: removals, pathSignature: signature))
        }
        return IndexSummary(total: notes.count, updated: upserts.count, removed: removals.count)
    }

    /// パスの一覧から作る、起動をまたいでも変わらない目印（FNV-1a、64 ビット）。
    static func signature(of paths: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in paths.sorted().joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

// MARK: - 参照する

public protocol FindBacklinksUseCase: Sendable {
    func callAsFunction(to path: String) async throws(NoteIndexError) -> [NoteSummary]
}

public struct FindBacklinksInteractor: FindBacklinksUseCase {
    private let index: any NoteIndexRepository

    public init(index: any NoteIndexRepository) {
        self.index = index
    }

    public func callAsFunction(to path: String) async throws(NoteIndexError) -> [NoteSummary] {
        try await index.backlinks(to: path)
    }
}

public protocol SearchNotesUseCase: Sendable {
    func callAsFunction(_ query: String) async throws(NoteIndexError) -> [SearchResult]
}

public struct SearchNotesInteractor: SearchNotesUseCase {
    private let index: any NoteIndexRepository

    public init(index: any NoteIndexRepository) {
        self.index = index
    }

    public func callAsFunction(_ query: String) async throws(NoteIndexError) -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return try await index.search(query, limit: 100)
    }
}

public protocol ListTagsUseCase: Sendable {
    func callAsFunction() async throws(NoteIndexError) -> [TagCount]
}

public struct ListTagsInteractor: ListTagsUseCase {
    private let index: any NoteIndexRepository

    public init(index: any NoteIndexRepository) {
        self.index = index
    }

    public func callAsFunction() async throws(NoteIndexError) -> [TagCount] {
        try await index.tags()
    }
}

public protocol FindNotesByTagUseCase: Sendable {
    func callAsFunction(_ tag: String) async throws(NoteIndexError) -> [NoteSummary]
}

public struct FindNotesByTagInteractor: FindNotesByTagUseCase {
    private let index: any NoteIndexRepository

    public init(index: any NoteIndexRepository) {
        self.index = index
    }

    public func callAsFunction(_ tag: String) async throws(NoteIndexError) -> [NoteSummary] {
        try await index.notes(taggedWith: tag)
    }
}

public protocol ObserveNoteIndexUseCase: Sendable {
    func callAsFunction() -> AsyncStream<Void>
}

public struct ObserveNoteIndexInteractor: ObserveNoteIndexUseCase {
    private let index: any NoteIndexRepository

    public init(index: any NoteIndexRepository) {
        self.index = index
    }

    public func callAsFunction() -> AsyncStream<Void> {
        index.changes()
    }
}

// MARK: - Vault を同期する

/// Vault の木を読み、索引を最新にする。画面を開いたときと、Vault が変わったときに呼ぶ。
public protocol SyncVaultUseCase: Sendable {
    /// 木を返す。索引の更新に失敗しても、木は返す（索引は次の同期で作り直せるため）。
    func callAsFunction() async throws(VaultError) -> VaultNode
}

public struct SyncVaultInteractor: SyncVaultUseCase {
    private let vault: any VaultRepository
    private let indexVault: any IndexVaultUseCase

    public init(vault: any VaultRepository, indexVault: any IndexVaultUseCase) {
        self.vault = vault
        self.indexVault = indexVault
    }

    public func callAsFunction() async throws(VaultError) -> VaultNode {
        let tree = try await vault.loadTree()
        _ = try? await indexVault()
        return tree
    }
}
