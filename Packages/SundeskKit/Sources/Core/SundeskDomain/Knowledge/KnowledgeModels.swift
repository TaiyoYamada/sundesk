//
//  KnowledgeModels.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// ノートを見出しで区切った一片。RAG の検索と、知識グラフの出現の単位。
public struct NoteChunk: Hashable, Sendable, Identifiable {
    /// `<ノートのパス>#<番号>`。
    public let id: String
    public let notePath: String
    public let noteTitle: String
    /// 見出しの階層（ノートのタイトルから、この節の見出しまで）。
    public let headingPath: [String]
    /// 節の本文（Markdown のまま。数式やコードを含む）。LLM に渡す。
    public let text: String
    /// コードと数式を除いた本文。概念の抽出に使う。
    public let plainText: String
    /// ファイルの中での節の行番号（1 始まり）。出典から開くときに使う。
    public let line: Int

    public init(
        id: String, notePath: String, noteTitle: String, headingPath: [String], text: String, plainText: String,
        line: Int
    ) {
        self.id = id
        self.notePath = notePath
        self.noteTitle = noteTitle
        self.headingPath = headingPath
        self.text = text
        self.plainText = plainText
        self.line = line
    }
}

/// 知識グラフの点（概念）。
public struct Concept: Hashable, Sendable, Identifiable {
    public let id: Int
    public let label: String
    public let normalized: String
    /// 用語としての重要度（C-value と出現数から）。
    public let score: Double
    public let frequency: Int
    /// グラフの中での中心性。
    public let pagerank: Double
    /// 分野のまとまり（コミュニティ）の番号。
    public let community: Int

    public init(
        id: Int, label: String, normalized: String, score: Double, frequency: Int, pagerank: Double, community: Int
    ) {
        self.id = id
        self.label = label
        self.normalized = normalized
        self.score = score
        self.frequency = frequency
        self.pagerank = pagerank
        self.community = community
    }
}

/// 概念の関係の種類。
public enum RelationKind: String, CaseIterable, Sendable {
    case cooccurrence
    case hierarchy
    case definition
    case isA = "is_a"
    case link
    case contains
    case similar
}

/// 知識グラフの線。
public struct ConceptRelation: Hashable, Sendable {
    public let source: Int
    public let target: Int
    public let kind: RelationKind
    public let weight: Double
    /// 根拠になったチャンク。
    public let evidence: String?

    public init(source: Int, target: Int, kind: RelationKind, weight: Double, evidence: String?) {
        self.source = source
        self.target = target
        self.kind = kind
        self.weight = weight
        self.evidence = evidence
    }
}

/// 概念がチャンクに出てきたこと。
public struct ConceptMention: Hashable, Sendable {
    public let concept: Int
    public let chunk: String
    public let count: Int

    public init(concept: Int, chunk: String, count: Int) {
        self.concept = concept
        self.chunk = chunk
        self.count = count
    }
}

/// 知識グラフの全体。
public struct KnowledgeGraph: Equatable, Sendable {
    public let concepts: [Concept]
    public let relations: [ConceptRelation]
    public let mentions: [ConceptMention]

    public init(concepts: [Concept], relations: [ConceptRelation], mentions: [ConceptMention]) {
        self.concepts = concepts
        self.relations = relations
        self.mentions = mentions
    }

    public static let empty = KnowledgeGraph(concepts: [], relations: [], mentions: [])
}

/// 概念の出どころ（インスペクタで、概念が出てくるノートの節を示す）。
public struct ConceptSource: Hashable, Sendable {
    public let chunk: NoteChunk
    public let count: Int

    public init(chunk: NoteChunk, count: Int) {
        self.chunk = chunk
        self.count = count
    }
}

/// 知識の作り直しの進み具合。
public enum KnowledgeBuildStep: Equatable, Sendable {
    case readingNotes(done: Int, total: Int)
    case embedding(done: Int, total: Int)
    case buildingGraph
    case saving
    case finished(concepts: Int, relations: Int, chunks: Int)
}

public enum KnowledgeError: Error, Equatable, Sendable {
    case vault(VaultError)
    /// エンジンが動いていない、または計算に失敗した。
    case engine(String)
    case storage(String)

    public var message: String {
        switch self {
        case .vault(let error): "Vault を読めませんでした: \(error)"
        case .engine(let message): message
        case .storage(let message): "知識を保存できませんでした: \(message)"
        }
    }
}

/// 隣の概念と、その関係。
public struct RelatedConcept: Hashable, Sendable {
    public let concept: Concept
    public let kinds: [RelationKind]
    public let weight: Double

    public init(concept: Concept, kinds: [RelationKind], weight: Double) {
        self.concept = concept
        self.kinds = kinds
        self.weight = weight
    }
}

extension KnowledgeGraph {
    /// 概念の隣（線でつながった概念）。同じ組の線はまとめ、重みの大きい順に並べる。
    public func neighbors(of conceptID: Int) -> [RelatedConcept] {
        let byID = Dictionary(concepts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped: [Int: (kinds: [RelationKind], weight: Double)] = [:]
        for relation in relations where relation.source == conceptID || relation.target == conceptID {
            let other = relation.source == conceptID ? relation.target : relation.source
            var entry = grouped[other, default: ([], 0)]
            if !entry.kinds.contains(relation.kind) { entry.kinds.append(relation.kind) }
            entry.weight += relation.weight
            grouped[other] = entry
        }
        return grouped.compactMap { id, entry in
            byID[id].map { RelatedConcept(concept: $0, kinds: entry.kinds, weight: entry.weight) }
        }
        .sorted { $0.weight > $1.weight }
    }

    /// 重要な概念から `limit` 個と、その間の線（同じ組はまとめ、重い順に `edgeLimit` 本まで。既定は `limit` の 4 倍）。
    public func subgraph(limit: Int, edgeLimit: Int? = nil) -> Subgraph {
        let top = concepts.sorted { $0.pagerank > $1.pagerank }.prefix(limit)
        let included = Set(top.map(\.id))
        var weights: [Pair: Double] = [:]
        for relation in relations where included.contains(relation.source) && included.contains(relation.target) {
            weights[Pair(relation.source, relation.target), default: 0] += relation.weight
        }
        let edges = weights.map { Subgraph.Edge(source: $0.key.lower, target: $0.key.upper, weight: $0.value) }
            .sorted { $0.weight > $1.weight }
            .prefix(edgeLimit ?? limit * 4)
        return Subgraph(concepts: Array(top), edges: Array(edges))
    }

    private struct Pair: Hashable {
        let lower: Int
        let upper: Int

        init(_ first: Int, _ second: Int) {
            lower = min(first, second)
            upper = max(first, second)
        }
    }
}

/// 知識グラフの一部（描くときに使う）。
public struct Subgraph: Equatable, Sendable {
    public struct Edge: Equatable, Sendable {
        public let source: Int
        public let target: Int
        public let weight: Double
    }

    public let concepts: [Concept]
    public let edges: [Edge]
}
