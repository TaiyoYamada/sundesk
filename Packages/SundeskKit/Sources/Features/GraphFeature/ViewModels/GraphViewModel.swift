//
//  GraphViewModel.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 知識グラフのタブ。グラフを読み、選んだ概念の隣と出どころをインスペクタに出す。
@MainActor
@Observable
public final class GraphViewModel {
    public enum State: Equatable, Sendable {
        case loading
        /// まだ知識を作っていない。
        case empty
        case ready
        case failed(message: String)
    }

    public private(set) var state: State = .loading
    public private(set) var nodes: [GraphNodeItem] = []
    public private(set) var edges: [GraphEdgeItem] = []
    public private(set) var communities: [CommunityItem] = []
    public private(set) var summary = ""
    public private(set) var selected: ConceptDetailItem?
    /// 作り直しの進み具合（作り直していなければ nil）。
    public private(set) var build: KnowledgeBuildItem?
    /// 作り直しに失敗したときのメッセージ。
    public var buildError: String?
    /// 検索の文字。一致した概念を目立たせる。
    public var searchText = "" {
        didSet { if searchText != oldValue { updateMatches() } }
    }
    public private(set) var matchingNodeIDs: Set<Int> = []
    /// 描く概念の数（重要なものから）。
    public var nodeLimit = 300 {
        didSet { if nodeLimit != oldValue { applyGraph() } }
    }
    public static let nodeLimits = [100, 300, 1000, 3000]

    @ObservationIgnored private let loadGraph: any LoadKnowledgeGraphUseCase
    @ObservationIgnored private let observeKnowledge: any ObserveKnowledgeUseCase
    @ObservationIgnored private let rebuildKnowledge: any RebuildKnowledgeUseCase
    @ObservationIgnored private let observeBuild: any ObserveKnowledgeBuildUseCase
    @ObservationIgnored private let findSources: any FindConceptSourcesUseCase
    @ObservationIgnored private var graph = KnowledgeGraph.empty

    public init(
        loadGraph: any LoadKnowledgeGraphUseCase,
        observeKnowledge: any ObserveKnowledgeUseCase,
        rebuildKnowledge: any RebuildKnowledgeUseCase,
        observeBuild: any ObserveKnowledgeBuildUseCase,
        findSources: any FindConceptSourcesUseCase
    ) {
        self.loadGraph = loadGraph
        self.observeKnowledge = observeKnowledge
        self.rebuildKnowledge = rebuildKnowledge
        self.observeBuild = observeBuild
        self.findSources = findSources
    }

    // MARK: - 読み込み

    /// グラフを読み、知識が入れ替わるたびに読み直す。
    public func observe() async {
        await load()
        for await _ in observeKnowledge() {
            await load()
        }
    }

    /// 作り直しの進み具合を見張る。
    public func observeBuildProgress() async {
        for await step in await observeBuild() {
            build = step.flatMap(KnowledgeBuildItem.init)
        }
    }

    public func load() async {
        do {
            graph = try await loadGraph()
            state = graph.concepts.isEmpty ? .empty : .ready
            applyGraph()
        } catch {
            state = .failed(message: error.message)
        }
    }

    /// ノートから知識を作り直す（エンジンを使う）。
    public func rebuild() async {
        buildError = nil
        do {
            try await rebuildKnowledge()
        } catch {
            buildError = error.message
        }
    }

    // MARK: - 選択

    public func select(conceptID: Int?) async {
        guard let conceptID, let concept = graph.concepts.first(where: { $0.id == conceptID }) else {
            selected = nil
            return
        }
        let related = graph.neighbors(of: conceptID).prefix(30).map(RelatedConceptItem.init)
        selected = ConceptDetailItem(concept: concept, related: Array(related), sources: [])
        let sources = (try? await findSources(concept: conceptID, in: graph)) ?? []
        guard selected?.id == conceptID else { return }
        selected = ConceptDetailItem(
            concept: concept, related: Array(related), sources: sources.prefix(30).map(ConceptSourceItem.init))
    }

    // MARK: - 内部

    private func applyGraph() {
        let subgraph = graph.subgraph(limit: nodeLimit)
        let maxRank = subgraph.concepts.map(\.pagerank).max() ?? 1
        let index = Dictionary(
            subgraph.concepts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        nodes = subgraph.concepts.map { concept in
            GraphNodeItem(
                id: concept.id, label: concept.label,
                radius: 3 + 13 * (concept.pagerank / max(maxRank, .leastNonzeroMagnitude)).squareRoot(),
                community: concept.community)
        }
        let maxWeight = subgraph.edges.map(\.weight).max() ?? 1
        edges = subgraph.edges.compactMap { edge in
            guard let source = index[edge.source], let target = index[edge.target] else { return nil }
            return GraphEdgeItem(source: source, target: target, weight: 0.5 + 1.5 * edge.weight / max(maxWeight, 1e-9))
        }
        var groups: [Int: [Concept]] = [:]
        for concept in subgraph.concepts { groups[concept.community, default: []].append(concept) }
        communities = groups.map { community, members in
            CommunityItem(
                id: community, size: members.count,
                topLabels: members.sorted { $0.pagerank > $1.pagerank }.prefix(3).map(\.label))
        }
        .sorted { $0.size > $1.size }
        summary = "概念 \(graph.concepts.count)・関係 \(graph.relations.count)"
        updateMatches()
    }

    private func updateMatches() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        matchingNodeIDs =
            query.isEmpty ? [] : Set(nodes.filter { $0.label.localizedStandardContains(query) }.map(\.id))
    }
}

// MARK: - 表示用の型

/// グラフの点。
public struct GraphNodeItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let radius: Double
    public let community: Int
}

/// グラフの線（`nodes` の添字でつなぐ）。
public struct GraphEdgeItem: Hashable, Sendable {
    public let source: Int
    public let target: Int
    public let weight: Double
}

/// 分野のまとまり。
public struct CommunityItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let size: Int
    public let topLabels: [String]
}

/// 選んだ概念の詳細。
public struct ConceptDetailItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let community: Int
    public let importance: String
    public let frequency: Int
    public let related: [RelatedConceptItem]
    public let sources: [ConceptSourceItem]

    init(concept: Concept, related: [RelatedConceptItem], sources: [ConceptSourceItem]) {
        id = concept.id
        label = concept.label
        community = concept.community
        importance = String(format: "%.4f", concept.pagerank)
        frequency = concept.frequency
        self.related = related
        self.sources = sources
    }
}

public struct RelatedConceptItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    /// 関係の種類（「共起」「定義」など）。
    public let kinds: String

    init(_ related: RelatedConcept) {
        id = related.concept.id
        label = related.concept.label
        kinds = related.kinds.map(\.title).joined(separator: "・")
    }
}

public struct ConceptSourceItem: Identifiable, Hashable, Sendable {
    public var id: String { chunkID }
    public let chunkID: String
    public let path: String
    public let title: String
    /// 見出しの階層（ノートのタイトルを除く）。
    public let heading: String
    public let line: Int
    public let snippet: String

    init(_ source: ConceptSource) {
        chunkID = source.chunk.id
        path = source.chunk.notePath
        title = source.chunk.noteTitle
        heading = source.chunk.headingPath.dropFirst().joined(separator: " › ")
        line = source.chunk.line
        snippet = String(source.chunk.plainText.replacing(/\s+/, with: " ").prefix(80))
    }
}

/// 知識の作り直しの進み具合。
public struct KnowledgeBuildItem: Hashable, Sendable {
    public let title: String
    /// 0〜1。分からなければ nil。
    public let fraction: Double?

    init?(_ step: KnowledgeBuildStep) {
        switch step {
        case .readingNotes(let done, let total):
            title = "ノートを読んでいます（\(done)/\(total)）"
            fraction = total == 0 ? nil : Double(done) / Double(total) * 0.2
        case .embedding(let done, let total):
            title = "埋め込みを計算しています（\(done)/\(total)）"
            fraction = total == 0 ? nil : 0.2 + Double(done) / Double(total) * 0.5
        case .buildingGraph:
            title = "知識グラフを作っています"
            fraction = nil
        case .saving:
            title = "保存しています"
            fraction = nil
        case .finished:
            return nil
        }
    }
}

extension RelationKind {
    /// 画面に出す名前。
    public var title: String {
        switch self {
        case .cooccurrence: "共起"
        case .hierarchy: "見出し"
        case .definition: "定義"
        case .isA: "種類"
        case .link: "リンク"
        case .contains: "包含"
        case .similar: "類似"
        }
    }
}
