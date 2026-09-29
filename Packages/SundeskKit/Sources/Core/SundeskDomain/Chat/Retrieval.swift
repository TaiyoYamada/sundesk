//
//  Retrieval.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 検索で見つけたチャンク。
public struct RetrievedChunk: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case vector
        case keyword
        case graph
    }

    public let chunk: NoteChunk
    public let score: Double
    /// どの検索で見つかったか。
    public let sources: Set<Source>

    public init(chunk: NoteChunk, score: Double, sources: Set<Source>) {
        self.chunk = chunk
        self.score = score
        self.sources = sources
    }
}

/// 質問に関係するノートの節を探す。3 つの検索（意味、語、知識グラフ）を組み合わせる。
public protocol RetrieveContextUseCase: Sendable {
    func callAsFunction(_ question: String, limit: Int) async throws(KnowledgeError) -> [RetrievedChunk]
}

public struct RetrieveContextInteractor: RetrieveContextUseCase {
    private let repository: any KnowledgeRepository
    private let engine: any KnowledgeEngine
    /// 1 つの検索から候補にする数。
    private let candidates: Int

    public init(repository: any KnowledgeRepository, engine: any KnowledgeEngine, candidates: Int = 20) {
        self.repository = repository
        self.engine = engine
        self.candidates = candidates
    }

    public func callAsFunction(_ question: String, limit: Int) async throws(KnowledgeError) -> [RetrievedChunk] {
        let chunks = try await repository.allChunks()
        guard !chunks.isEmpty else { return [] }
        let byID = Dictionary(chunks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var rankings: [ReciprocalRankFusion.Ranking] = []
        // 意味の近さ（エンジンが動いていなければ飛ばす）
        if let vector = try? await engine.embed([question], kind: .query).vectors.first,
            let nearest = try? await repository.nearestChunks(to: vector, limit: candidates)
        {
            rankings.append(.init(source: .vector, ids: nearest.map(\.chunkID)))
        }
        rankings.append(.init(source: .keyword, ids: KeywordSearch.rank(question, in: chunks, limit: candidates)))
        let graph = try await repository.graph()
        let byGraph = GraphSearch.rank(question, in: graph, limit: candidates)
        if !byGraph.isEmpty {
            // 知識グラフに入っていないチャンク（論文の PDF など）は、この検索では出てこられない
            let mentioned = Set(graph.mentions.map(\.chunk))
            rankings.append(.init(source: .graph, ids: byGraph, canContain: { mentioned.contains($0) }))
        }

        return ReciprocalRankFusion.fuse(rankings, limit: limit).compactMap { fused in
            byID[fused.id].map { RetrievedChunk(chunk: $0, score: fused.score, sources: fused.sources) }
        }
    }
}

/// 複数の順位を、順位の逆数の和でまとめる（Reciprocal Rank Fusion）。
///
/// そもそも出てこられない検索がある候補（知識グラフに入らない PDF の節など）は、
/// 出てこられる検索の数で割って比べる。割らないと、どれだけ近くても上位に来られない。
enum ReciprocalRankFusion {
    struct Ranking {
        let source: RetrievedChunk.Source
        let ids: [String]
        /// この検索で出てくる可能性があるか。
        var canContain: (String) -> Bool = { _ in true }
    }

    struct Fused {
        let id: String
        let score: Double
        let sources: Set<RetrievedChunk.Source>
    }

    /// - Parameter smoothing: 上位の順位の差を和らげる定数（よく使われる 60）。
    static func fuse(_ rankings: [Ranking], limit: Int, smoothing: Double = 60) -> [Fused] {
        var sums: [String: Double] = [:]
        var sources: [String: Set<RetrievedChunk.Source>] = [:]
        for ranking in rankings {
            for (rank, id) in ranking.ids.enumerated() {
                sums[id, default: 0] += 1 / (smoothing + Double(rank + 1))
                sources[id, default: []].insert(ranking.source)
            }
        }
        let scores = sums.map { id, sum in
            let eligible = rankings.filter { $0.canContain(id) }.count
            return (key: id, value: sum * Double(rankings.count) / Double(max(eligible, 1)))
        }
        return scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { Fused(id: $0.key, score: $0.value, sources: sources[$0.key] ?? []) }
    }
}

/// 語の一致による検索。日本語は語の区切りがないので、2 文字ずつの組（bigram）で比べる。
enum KeywordSearch {
    static func rank(_ query: String, in chunks: [NoteChunk], limit: Int) -> [String] {
        let terms = bigrams(query)
        guard !terms.isEmpty else { return [] }
        let documents = chunks.map { bigrams($0.headingPath.joined(separator: " ") + " " + $0.plainText) }
        // 多くのチャンクに出る組ほど軽くする（IDF）
        var documentFrequency: [String: Int] = [:]
        for document in documents {
            for term in terms where document.contains(term) { documentFrequency[term, default: 0] += 1 }
        }
        let count = Double(chunks.count)
        let scored = zip(chunks, documents).compactMap { chunk, document -> (String, Double)? in
            let score = terms.reduce(0.0) { total, term in
                guard document.contains(term) else { return total }
                return total + log(1 + count / Double(documentFrequency[term] ?? 1))
            }
            return score > 0 ? (chunk.id, score) : nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(limit).map(\.0)
    }

    static func bigrams(_ text: String) -> Set<String> {
        let normalized = Array(
            text.precomposedStringWithCompatibilityMapping.lowercased()
                .filter { $0.isLetter || $0.isNumber })
        guard normalized.count >= 2 else { return normalized.isEmpty ? [] : [String(normalized)] }
        return Set((0..<(normalized.count - 1)).map { String(normalized[$0...($0 + 1)]) })
    }
}

/// 知識グラフによる検索。質問に出てくる概念と、その隣の概念が多く出るチャンクを選ぶ。
enum GraphSearch {
    static func rank(_ query: String, in graph: KnowledgeGraph, limit: Int) -> [String] {
        let normalizedQuery = query.precomposedStringWithCompatibilityMapping.lowercased()
        let matched = graph.concepts
            .filter { $0.normalized.count >= 2 && normalizedQuery.contains($0.normalized) }
            .sorted { $0.normalized.count > $1.normalized.count }
            .prefix(5)
        guard !matched.isEmpty else { return [] }
        var weights: [Int: Double] = [:]
        for concept in matched {
            weights[concept.id, default: 0] += 2
            for neighbor in graph.neighbors(of: concept.id).prefix(5) {
                weights[neighbor.concept.id, default: 0] += 0.5
            }
        }
        var scores: [String: Double] = [:]
        for mention in graph.mentions {
            if let weight = weights[mention.concept] {
                scores[mention.chunk, default: 0] += weight * log(1 + Double(mention.count))
            }
        }
        return scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
    }
}
