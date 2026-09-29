//
//  SwiftDataNoteIndex.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SwiftData
import Synchronization

/// ノートの索引を SwiftData で持つ。書き込みはこの actor の中（バックグラウンド）で行う。
public actor SwiftDataNoteIndex: NoteIndexRepository, ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    nonisolated private let broadcaster = ChangeBroadcaster()

    private static let pathSignatureKey = "pathSignature"

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    public func stamps() async throws -> [String: String] {
        let notes = try modelContext.fetch(FetchDescriptor<NoteRecord>())
        return Dictionary(notes.map { ($0.path, $0.stamp) }, uniquingKeysWith: { first, _ in first })
    }

    public func pathSignature() async throws -> String? {
        try metadata(Self.pathSignatureKey)?.value
    }

    public func apply(_ changes: NoteIndexChanges) async throws {
        for note in changes.upserts {
            let path = note.path
            if let existing = try modelContext.fetch(
                FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.path == path })
            ).first {
                existing.title = note.title
                existing.tags = note.tags
                existing.body = note.body
                existing.stamp = note.stamp
            } else {
                modelContext.insert(
                    NoteRecord(path: path, title: note.title, tags: note.tags, body: note.body, stamp: note.stamp))
            }
            try modelContext.delete(model: NoteLinkRecord.self, where: #Predicate { $0.sourcePath == path })
            for target in note.linkedPaths {
                modelContext.insert(NoteLinkRecord(sourcePath: path, targetPath: target))
            }
        }

        for path in changes.removals {
            try modelContext.delete(model: NoteRecord.self, where: #Predicate { $0.path == path })
            try modelContext.delete(model: NoteLinkRecord.self, where: #Predicate { $0.sourcePath == path })
        }

        if let signature = try metadata(Self.pathSignatureKey) {
            signature.value = changes.pathSignature
        } else {
            modelContext.insert(IndexMetadataRecord(key: Self.pathSignatureKey, value: changes.pathSignature))
        }

        try modelContext.save()
        broadcaster.send()
    }

    public func backlinks(to path: String) async throws -> [NoteSummary] {
        let links = try modelContext.fetch(
            FetchDescriptor<NoteLinkRecord>(predicate: #Predicate { $0.targetPath == path }))
        let sources = Set(links.map(\.sourcePath))
        let notes = try modelContext.fetch(
            FetchDescriptor<NoteRecord>(predicate: #Predicate { sources.contains($0.path) }))
        return notes.map { NoteSummary(path: $0.path, title: $0.title) }.sorted(by: Self.byTitle)
    }

    public func search(_ query: String, limit: Int) async throws -> [SearchResult] {
        let notes = try modelContext.fetch(
            FetchDescriptor<NoteRecord>(
                predicate: #Predicate {
                    $0.title.localizedStandardContains(query) || $0.body.localizedStandardContains(query)
                }
            )
        )
        // タイトルに一致したものを先に出す
        let ranked = notes.sorted { lhs, rhs in
            let (lhsInTitle, rhsInTitle) = (
                lhs.title.localizedStandardContains(query), rhs.title.localizedStandardContains(query)
            )
            return lhsInTitle != rhsInTitle
                ? lhsInTitle : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return ranked.prefix(limit).map { note in
            SearchResult(path: note.path, title: note.title, snippet: Self.snippet(of: note.body, around: query))
        }
    }

    public func tags() async throws -> [TagCount] {
        var counts: [String: (name: String, count: Int)] = [:]
        for note in try modelContext.fetch(FetchDescriptor<NoteRecord>()) {
            for tag in Set(note.tags) {
                counts[tag.lowercased(), default: (tag, 0)].count += 1
            }
        }
        return counts.values
            .map { TagCount(name: $0.name, count: $0.count) }
            .sorted {
                $0.count != $1.count
                    ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    public func notes(taggedWith tag: String) async throws -> [NoteSummary] {
        let tag = tag.lowercased()
        return try modelContext.fetch(FetchDescriptor<NoteRecord>())
            .filter { $0.tags.contains { $0.lowercased() == tag || $0.lowercased().hasPrefix(tag + "/") } }
            .map { NoteSummary(path: $0.path, title: $0.title) }
            .sorted(by: Self.byTitle)
    }

    nonisolated public func changes() -> AsyncStream<Void> {
        broadcaster.subscribe()
    }

    // MARK: - 内部

    private func metadata(_ key: String) throws -> IndexMetadataRecord? {
        try modelContext.fetch(FetchDescriptor<IndexMetadataRecord>(predicate: #Predicate { $0.key == key })).first
    }

    private static func byTitle(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// 一致した箇所の前後 40 文字ほどを、1 行にして返す。
    static func snippet(of body: String, around query: String, radius: Int = 40) -> String {
        let flat = body.replacing(/\s+/, with: " ")
        guard let range = flat.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        else { return String(flat.prefix(radius * 2)) }
        let start = flat.index(range.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}

/// 複数の購読者に「変わった」を知らせる。
final class ChangeBroadcaster: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    func subscribe() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
        }
        return stream
    }

    func send() {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield()
        }
    }
}
