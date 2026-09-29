//
//  EngineKnowledgeGateway.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SundeskEngineClient

/// 埋め込みと知識グラフの計算を、Python のエンジンに頼む（docs/engine-api.md）。
public struct EngineKnowledgeGateway: KnowledgeEngine {
    private let process: EngineProcess
    private let embeddingModel: @Sendable () -> String?

    /// - Parameter embeddingModel: 埋め込みに使うモデル。nil ならエンジンの既定。
    public init(process: EngineProcess, embeddingModel: @escaping @Sendable () -> String? = { nil }) {
        self.process = process
        self.embeddingModel = embeddingModel
    }

    public func embed(_ texts: [String], kind: EmbeddingKind) async throws(KnowledgeError) -> EmbeddingBatch {
        let client = try await client()
        let response = try await call {
            try await client.post(
                "embeddings", body: EmbeddingRequest(texts: texts, kind: kind.rawValue, model: embeddingModel()),
                as: EmbeddingResponse.self)
        }
        return EmbeddingBatch(model: response.model, vectors: response.vectors)
    }

    public func buildGraph(notes: [GraphSourceNote], similarity: Bool) async throws(KnowledgeError) -> KnowledgeGraph {
        let client = try await client()
        let request = GraphRequest(
            notes: notes.map { note in
                GraphRequest.Note(
                    path: note.path, title: note.title, links: note.links,
                    chunks: note.chunks.map { .init(id: $0.id, headingPath: $0.headingPath, text: $0.plainText) })
            },
            options: .init(maxConcepts: 1500, minFrequency: 2, similarity: similarity))
        let response = try await call { try await client.post("graph/build", body: request, as: GraphResponse.self) }
        return KnowledgeGraph(
            concepts: response.concepts.map {
                Concept(
                    id: $0.id, label: $0.label, normalized: $0.normalized, score: $0.score, frequency: $0.frequency,
                    pagerank: $0.pagerank, community: $0.community)
            },
            relations: response.relations.compactMap { relation in
                RelationKind(rawValue: relation.kind).map {
                    ConceptRelation(
                        source: relation.source, target: relation.target, kind: $0, weight: relation.weight,
                        evidence: relation.evidence)
                }
            },
            mentions: response.mentions.map { ConceptMention(concept: $0.concept, chunk: $0.chunk, count: $0.count) }
        )
    }

    private func client() async throws(KnowledgeError) -> EngineClient {
        do {
            return try await process.runningClient()
        } catch {
            throw .engine(EngineMapper.failure(from: error).message)
        }
    }

    private func call<T>(_ body: () async throws -> T) async throws(KnowledgeError) -> T {
        do {
            return try await body()
        } catch let error as EngineClientError {
            throw .engine(error.message)
        } catch {
            throw .engine(error.localizedDescription)
        }
    }
}

// MARK: - JSON

private struct EmbeddingRequest: Encodable {
    let texts: [String]
    let kind: String
    let model: String?
}

private struct EmbeddingResponse: Decodable {
    let model: String
    let dimension: Int
    let vectors: [[Float]]
}

private struct GraphRequest: Encodable {
    struct Note: Encodable {
        let path: String
        let title: String
        let links: [String]
        let chunks: [Chunk]
    }

    struct Chunk: Encodable {
        let id: String
        let headingPath: [String]
        let text: String
    }

    struct Options: Encodable {
        let maxConcepts: Int
        let minFrequency: Int
        let similarity: Bool
    }

    let notes: [Note]
    let options: Options
}

private struct GraphResponse: Decodable {
    struct ConceptItem: Decodable {
        let id: Int
        let label: String
        let normalized: String
        let score: Double
        let frequency: Int
        let pagerank: Double
        let community: Int
    }

    struct MentionItem: Decodable {
        let concept: Int
        let chunk: String
        let count: Int
    }

    struct RelationItem: Decodable {
        let source: Int
        let target: Int
        let kind: String
        let weight: Double
        let evidence: String?
    }

    let concepts: [ConceptItem]
    let mentions: [MentionItem]
    let relations: [RelationItem]
}
