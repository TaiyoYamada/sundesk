//
//  TestDoubles.swift
//  NotesFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

// NotesFeature のテストで使う UseCase の偽物。

struct OpenDocumentStub: OpenDocumentUseCase {
    var documents: [String: Document] = [:]

    func callAsFunction(path: String) async throws(VaultError) -> Document {
        guard let document = documents[path] else { throw .fileNotFound(path: path) }
        return document
    }

    static func markdown(_ path: String, source: String, analysis: NoteAnalysis) -> Document {
        Document(
            path: path,
            name: path,
            kind: .markdown,
            info: FileInfo(path: path, size: source.utf8.count, created: nil, modified: Date(timeIntervalSince1970: 0)),
            content: .markdown(source: source, analysis: analysis)
        )
    }

    static func file(_ path: String, kind: FileKind, content: DocumentContent) -> Document {
        Document(
            path: path,
            name: path,
            kind: kind,
            info: FileInfo(path: path, size: 0, created: nil, modified: Date(timeIntervalSince1970: 0)),
            content: content
        )
    }
}

/// 読むたびに中身を差し替えられる偽物（ファイルが外で書き換えられた場合を試す）。
final class MutableOpenDocumentStub: OpenDocumentUseCase, @unchecked Sendable {
    var document: Document

    init(_ document: Document) {
        self.document = document
    }

    func callAsFunction(path: String) async throws(VaultError) -> Document { document }
}

/// 保存した本文を記録する。`failure` を入れると保存に失敗する。
actor SaveDocumentSpy: SaveDocumentUseCase {
    private(set) var saved: [(path: String, text: String)] = []
    var failure: VaultError?

    func fail(with error: VaultError?) {
        failure = error
    }

    func callAsFunction(_ text: String, to path: String) async throws(VaultError) {
        if let failure { throw failure }
        saved.append((path, text))
    }
}

/// 見出しの行（`# ` で始まる行）だけを読む、簡単な解析。
struct AnalyzeNoteStub: AnalyzeNoteUseCase {
    func callAsFunction(_ source: String, path: String) -> NoteAnalysis {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let headings = lines.enumerated().compactMap { index, line -> NoteHeading? in
            guard let match = line.wholeMatch(of: /(#+) (.+)/) else { return nil }
            return NoteHeading(level: match.output.1.count, text: String(match.output.2), line: index + 1)
        }
        return NoteAnalysis(
            title: headings.first { $0.level == 1 }?.text, properties: [], tags: [], links: [], headings: headings,
            body: source)
    }
}

struct FindBacklinksStub: FindBacklinksUseCase {
    var backlinks: [String: [NoteSummary]] = [:]
    func callAsFunction(to path: String) async throws(NoteIndexError) -> [NoteSummary] { backlinks[path] ?? [] }
}

struct LocateFileStub: LocateFileUseCase {
    func callAsFunction(_ path: String) -> URL { URL(filePath: "/vault").appending(path: path) }
    func vaultRoot() -> URL { URL(filePath: "/vault") }
}

struct SyncVaultStub: SyncVaultUseCase {
    func callAsFunction() async throws(VaultError) -> VaultNode {
        VaultNode(
            id: "",
            name: "Vault",
            kind: .folder,
            children: [
                VaultNode(id: "ホーム.md", name: "ホーム.md", kind: .markdown),
                VaultNode(
                    id: "量子計算",
                    name: "量子計算",
                    kind: .folder,
                    children: [VaultNode(id: "量子計算/量子ビット.md", name: "量子ビット.md", kind: .markdown)]
                ),
            ]
        )
    }
}

struct ObserveChangesStub: ObserveVaultChangesUseCase {
    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

struct SearchStub: SearchNotesUseCase {
    func callAsFunction(_ query: String) async throws(NoteIndexError) -> [SearchResult] {
        [SearchResult(path: "固有値.md", title: "固有値", snippet: "…固有値…")]
    }
}

struct TagsStub: ListTagsUseCase, FindNotesByTagUseCase {
    func callAsFunction() async throws(NoteIndexError) -> [TagCount] { [TagCount(name: "量子計算", count: 1)] }
    func callAsFunction(_ tag: String) async throws(NoteIndexError) -> [NoteSummary] {
        [NoteSummary(path: "量子計算/量子ビット.md", title: "量子ビット")]
    }
}

struct ObserveIndexStub: ObserveNoteIndexUseCase {
    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
