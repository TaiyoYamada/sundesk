//
//  SwiftDataKnowledgeRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import Testing

@Suite("SwiftDataKnowledgeRepository")
struct SwiftDataKnowledgeRepositoryTests {
    private func chunk(_ id: String, path: String = "a.md") -> NoteChunk {
        NoteChunk(
            id: id, notePath: path, noteTitle: "A", headingPath: ["A", id], text: "本文 \(id)", plainText: "本文", line: 3)
    }

    private let graph = KnowledgeGraph(
        concepts: [
            Concept(id: 1, label: "行列", normalized: "行列", score: 2, frequency: 4, pagerank: 0.2, community: 1),
            Concept(id: 0, label: "固有値", normalized: "固有値", score: 3, frequency: 5, pagerank: 0.4, community: 0),
        ],
        relations: [ConceptRelation(source: 0, target: 1, kind: .isA, weight: 1.5, evidence: "a.md#0")],
        mentions: [ConceptMention(concept: 0, chunk: "a.md#0", count: 2)]
    )

    private func makeRepository() throws -> SwiftDataKnowledgeRepository {
        SwiftDataKnowledgeRepository(modelContainer: try KnowledgeStore.makeContainer(url: nil))
    }

    @Test("保存したチャンクとグラフを読み戻せる")
    func roundTrip() async throws {
        let repository = try makeRepository()

        try await repository.replace(
            chunks: [
                EmbeddedChunk(chunk: chunk("a.md#0"), contentHash: "h0", embedding: [1, 0]),
                EmbeddedChunk(chunk: chunk("a.md#1"), contentHash: "h1", embedding: nil),
            ],
            graph: graph, embeddingModel: "ruri")

        #expect(try await repository.graph().concepts.map(\.id) == [0, 1])
        #expect(try await repository.graph().relations == graph.relations)
        #expect(try await repository.graph().mentions == graph.mentions)
        #expect(try await repository.allChunks().map(\.id) == ["a.md#0", "a.md#1"])
        #expect(try await repository.chunks(ids: ["a.md#1", "a.md#0"]).map(\.id) == ["a.md#1", "a.md#0"])
        #expect(try await repository.storedEmbeddings(model: "ruri") == ["h0": [1, 0]])
        #expect(try await repository.storedEmbeddings(model: "他のモデル").isEmpty)
    }

    @Test("入れ替えると前の知識は消える")
    func replaceRemovesOld() async throws {
        let repository = try makeRepository()
        try await repository.replace(
            chunks: [EmbeddedChunk(chunk: chunk("a.md#0"), contentHash: "h0", embedding: [1, 0])], graph: graph,
            embeddingModel: "ruri")

        try await repository.replace(chunks: [], graph: .empty, embeddingModel: nil)

        #expect(try await repository.allChunks().isEmpty)
        #expect(try await repository.graph() == .empty)
    }

    @Test("ベクトル検索は内積の大きい順に返す")
    func nearestChunks() async throws {
        let repository = try makeRepository()
        try await repository.replace(
            chunks: [
                EmbeddedChunk(chunk: chunk("a.md#0"), contentHash: "h0", embedding: [1, 0]),
                EmbeddedChunk(chunk: chunk("a.md#1"), contentHash: "h1", embedding: [0.6, 0.8]),
                EmbeddedChunk(chunk: chunk("a.md#2"), contentHash: "h2", embedding: [0, 1]),
            ],
            graph: .empty, embeddingModel: "ruri")

        let nearest = try await repository.nearestChunks(to: [0, 1], limit: 2)

        #expect(nearest.map(\.chunkID) == ["a.md#2", "a.md#1"])
        #expect(abs(nearest[1].score - 0.8) < 1e-5)
    }

    @Test("入れ替えたら知らせる")
    func notifiesChanges() async throws {
        let repository = try makeRepository()
        var changes = repository.changes().makeAsyncIterator()

        try await repository.replace(chunks: [], graph: graph, embeddingModel: nil)

        #expect(await changes.next() != nil)
    }
}
