//
//  SwiftDataKnowledgeRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Accelerate
import Foundation
import SundeskDomain
import SwiftData

/// 知識を SwiftData で持つ。ベクトル検索は、埋め込みをメモリに並べて総当たりで行う（数千件なら十分に速い）。
public actor SwiftDataKnowledgeRepository: KnowledgeRepository, ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    nonisolated private let broadcaster = ChangeBroadcaster()

    /// 検索用に並べた埋め込み（行がチャンク）。知識を入れ替えたら作り直す。
    private var matrix: EmbeddingMatrix?

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    public func replace(
        chunks: [EmbeddedChunk], graph: KnowledgeGraph, embeddingModel: String?
    ) async throws(KnowledgeError) {
        try storage {
            try modelContext.delete(model: ChunkRecord.self)
            try modelContext.delete(model: ConceptRecord.self)
            try modelContext.delete(model: RelationRecord.self)
            try modelContext.delete(model: MentionRecord.self)
            for (ordinal, item) in chunks.enumerated() {
                let chunk = item.chunk
                modelContext.insert(
                    ChunkRecord(
                        chunkID: chunk.id, notePath: chunk.notePath, noteTitle: chunk.noteTitle,
                        headingPath: chunk.headingPath, text: chunk.text, plainText: chunk.plainText, line: chunk.line,
                        ordinal: ordinal, contentHash: item.contentHash, embedding: item.embedding.map(Self.data),
                        embeddingModel: item.embedding == nil ? nil : embeddingModel))
            }
            for concept in graph.concepts {
                modelContext.insert(
                    ConceptRecord(
                        conceptID: concept.id, label: concept.label, normalized: concept.normalized,
                        score: concept.score, frequency: concept.frequency, pagerank: concept.pagerank,
                        community: concept.community))
            }
            for relation in graph.relations {
                modelContext.insert(
                    RelationRecord(
                        source: relation.source, target: relation.target, kind: relation.kind.rawValue,
                        weight: relation.weight, evidence: relation.evidence))
            }
            for mention in graph.mentions {
                modelContext.insert(MentionRecord(concept: mention.concept, chunk: mention.chunk, count: mention.count))
            }
            try modelContext.save()
        }
        matrix = nil
        broadcaster.send()
    }

    public func graph() async throws(KnowledgeError) -> KnowledgeGraph {
        try storage {
            let concepts = try modelContext.fetch(FetchDescriptor<ConceptRecord>(sortBy: [SortDescriptor(\.conceptID)]))
                .map {
                    Concept(
                        id: $0.conceptID, label: $0.label, normalized: $0.normalized, score: $0.score,
                        frequency: $0.frequency, pagerank: $0.pagerank, community: $0.community)
                }
            let relations = try modelContext.fetch(FetchDescriptor<RelationRecord>()).compactMap { record in
                RelationKind(rawValue: record.kind).map {
                    ConceptRelation(
                        source: record.source, target: record.target, kind: $0, weight: record.weight,
                        evidence: record.evidence)
                }
            }
            let mentions = try modelContext.fetch(FetchDescriptor<MentionRecord>()).map {
                ConceptMention(concept: $0.concept, chunk: $0.chunk, count: $0.count)
            }
            return KnowledgeGraph(concepts: concepts, relations: relations, mentions: mentions)
        }
    }

    public func allChunks() async throws(KnowledgeError) -> [NoteChunk] {
        try storage {
            try modelContext.fetch(FetchDescriptor<ChunkRecord>(sortBy: [SortDescriptor(\.ordinal)])).map(Self.chunk)
        }
    }

    public func chunks(ids: [String]) async throws(KnowledgeError) -> [NoteChunk] {
        try storage {
            let records = try modelContext.fetch(
                FetchDescriptor<ChunkRecord>(predicate: #Predicate { ids.contains($0.chunkID) }))
            let byID = Dictionary(records.map { ($0.chunkID, Self.chunk($0)) }, uniquingKeysWith: { first, _ in first })
            return ids.compactMap { byID[$0] }
        }
    }

    public func storedEmbeddings(model: String) async throws(KnowledgeError) -> [String: [Float]] {
        try storage {
            let records = try modelContext.fetch(
                FetchDescriptor<ChunkRecord>(predicate: #Predicate { $0.embeddingModel == model }))
            var result: [String: [Float]] = [:]
            for record in records {
                if let data = record.embedding { result[record.contentHash] = Self.vector(data) }
            }
            return result
        }
    }

    public func nearestChunks(to vector: [Float], limit: Int) async throws(KnowledgeError) -> [ScoredChunk] {
        let matrix = try loadMatrix()
        return matrix.nearest(to: vector, limit: limit)
    }

    nonisolated public func changes() -> AsyncStream<Void> {
        broadcaster.subscribe()
    }

    // MARK: - 内部

    private func loadMatrix() throws(KnowledgeError) -> EmbeddingMatrix {
        if let matrix { return matrix }
        let loaded = try storage {
            let records = try modelContext.fetch(
                FetchDescriptor<ChunkRecord>(
                    predicate: #Predicate { $0.embedding != nil }, sortBy: [SortDescriptor(\.ordinal)]))
            return EmbeddingMatrix(
                rows: records.compactMap { record in
                    record.embedding.map { (record.chunkID, Self.vector($0)) }
                })
        }
        matrix = loaded
        return loaded
    }

    private func storage<T>(_ body: () throws -> T) throws(KnowledgeError) -> T {
        do {
            return try body()
        } catch {
            throw .storage(error.localizedDescription)
        }
    }

    private static func chunk(_ record: ChunkRecord) -> NoteChunk {
        NoteChunk(
            id: record.chunkID, notePath: record.notePath, noteTitle: record.noteTitle,
            headingPath: record.headingPath, text: record.text, plainText: record.plainText, line: record.line)
    }

    static func data(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func vector(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// 埋め込みを行列に並べたもの。質問のベクトルとの内積を一度に計算する。
struct EmbeddingMatrix: Sendable {
    let ids: [String]
    let dimension: Int
    /// 行優先（チャンク数 × 次元）。
    let values: [Float]

    init(rows: [(String, [Float])]) {
        let dimension = rows.first?.1.count ?? 0
        let valid = rows.filter { $0.1.count == dimension }
        ids = valid.map(\.0)
        self.dimension = dimension
        values = valid.flatMap(\.1)
    }

    /// 内積の大きい順（埋め込みは長さ 1 に正規化してあるので、コサイン類似度と同じ）。
    func nearest(to query: [Float], limit: Int) -> [ScoredChunk] {
        guard dimension > 0, query.count == dimension, !ids.isEmpty else { return [] }
        var scores = [Float](repeating: 0, count: ids.count)
        values.withUnsafeBufferPointer { matrix in
            query.withUnsafeBufferPointer { vector in
                scores.withUnsafeMutableBufferPointer { result in
                    vDSP_mmul(
                        matrix.baseAddress!, 1, vector.baseAddress!, 1, result.baseAddress!, 1,
                        vDSP_Length(ids.count), 1, vDSP_Length(dimension))
                }
            }
        }
        return scores.indices
            .sorted { scores[$0] > scores[$1] }
            .prefix(limit)
            .map { ScoredChunk(chunkID: ids[$0], score: Double(scores[$0])) }
    }
}
