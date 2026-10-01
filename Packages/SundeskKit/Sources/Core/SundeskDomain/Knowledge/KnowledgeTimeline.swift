//
//  KnowledgeTimeline.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// 知識が育った順（ノートを作った順と、概念が初めて出てきたノート）。知識グラフで、育つ様子を再生するのに使う。
public struct KnowledgeTimeline: Equatable, Sendable {
    public struct Note: Equatable, Sendable {
        public let path: String
        public let title: String
        /// 作った日時（分からなければ、最後に変えた日時）。
        public let date: Date

        public init(path: String, title: String, date: Date) {
            self.path = path
            self.title = title
            self.date = date
        }
    }

    /// 作った順のノート（同じ日時なら、パスの順）。概念が出てくるノートだけ。
    public let notes: [Note]
    /// 概念 → 初めて出てきたノート（`notes` の添字）。
    public let firstNote: [Int: Int]

    public init(notes: [Note], firstNote: [Int: Int]) {
        self.notes = notes
        self.firstNote = firstNote
    }

    public static let empty = KnowledgeTimeline(notes: [], firstNote: [:])

    /// 概念が生まれた時（0〜1。最初のノートが 0、最後のノートが 1）。
    public func birth(of conceptID: Int) -> Double? {
        guard let index = firstNote[conceptID] else { return nil }
        return notes.count > 1 ? Double(index) / Double(notes.count - 1) : 0
    }

    /// 概念とノートと日時から作る。
    ///
    /// - Parameter notes: 出てきたノートのパス → 題名と日時。
    public static func make(mentions: [ConceptMention], notes: [String: (title: String, date: Date)]) -> Self {
        let ordered = notes.map { Note(path: $0.key, title: $0.value.title, date: $0.value.date) }
            .sorted { ($0.date, $0.path) < ($1.date, $1.path) }
        let position = Dictionary(
            ordered.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
        var first: [Int: Int] = [:]
        for mention in mentions {
            guard let index = position[notePath(ofChunk: mention.chunk)] else { continue }
            first[mention.concept] = min(first[mention.concept] ?? index, index)
        }
        return KnowledgeTimeline(notes: ordered, firstNote: first)
    }

    /// チャンクの ID（`<ノートのパス>#<番号>`）から、ノートのパスを取り出す。
    public static func notePath(ofChunk chunkID: String) -> String {
        guard let hash = chunkID.lastIndex(of: "#") else { return chunkID }
        return String(chunkID[..<hash])
    }
}

public protocol LoadKnowledgeTimelineUseCase: Sendable {
    func callAsFunction(for graph: KnowledgeGraph) async throws(KnowledgeError) -> KnowledgeTimeline
}

/// 概念が出てくるノートの、作った日時を調べて並べる。
public struct LoadKnowledgeTimelineInteractor: LoadKnowledgeTimelineUseCase {
    private let repository: any KnowledgeRepository
    private let vault: any VaultRepository

    public init(repository: any KnowledgeRepository, vault: any VaultRepository) {
        self.repository = repository
        self.vault = vault
    }

    public func callAsFunction(for graph: KnowledgeGraph) async throws(KnowledgeError) -> KnowledgeTimeline {
        // ノートごとに 1 つのチャンクを読んで、題名を知る
        var firstChunk: [String: String] = [:]
        for mention in graph.mentions {
            let path = KnowledgeTimeline.notePath(ofChunk: mention.chunk)
            if firstChunk[path] == nil { firstChunk[path] = mention.chunk }
        }
        let chunks = try await repository.chunks(ids: Array(firstChunk.values))
        let titles = Dictionary(chunks.map { ($0.notePath, $0.noteTitle) }, uniquingKeysWith: { first, _ in first })
        var notes: [String: (title: String, date: Date)] = [:]
        for path in firstChunk.keys {
            guard let info = try? await vault.fileInfo(at: path) else { continue }
            notes[path] = (titles[path] ?? path, info.created ?? info.modified)
        }
        return KnowledgeTimeline.make(mentions: graph.mentions, notes: notes)
    }
}
