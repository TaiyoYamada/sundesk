//
//  GraphViewModel.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain
import SundeskGraphRenderer

/// 知識グラフのタブ。グラフを読み、選んだ概念の隣と出どころをインスペクタに出す。
///
/// 2 つの概念の間の経路と、ノートを作った順に知識が育つ様子（時間の再生）も受け持つ。
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
    public var nodeLimit = 1000 {
        didSet { if nodeLimit != oldValue { applyGraph() } }
    }
    public static let nodeLimits = [100, 300, 1000, 3000]
    /// 選んだ概念から、⇧ を押して選んだ概念までの経路（たどる順）。
    public private(set) var path: [PathStepItem] = []
    /// 経路が見つからなかったときのメッセージ。
    public private(set) var pathMessage: String?
    /// ノートを作った順（時間の再生の目盛り）。空なら再生できない。
    public private(set) var timeline: [TimelineStepItem] = []
    /// グラフの描画の状態（配置、カメラ、選択）。タブを切り替えても保つよう、画面ではなくここに置く。
    @ObservationIgnored public private(set) lazy var canvas = GraphCanvasModel()
    /// ノートを開く（パス、行番号）。画面かインスペクタが渡す。
    @ObservationIgnored public var noteOpener: ((String, Int) -> Void)?

    @ObservationIgnored private let loadGraph: any LoadKnowledgeGraphUseCase
    @ObservationIgnored private let observeKnowledge: any ObserveKnowledgeUseCase
    @ObservationIgnored private let rebuildKnowledge: any RebuildKnowledgeUseCase
    @ObservationIgnored private let observeBuild: any ObserveKnowledgeBuildUseCase
    @ObservationIgnored private let findSources: any FindConceptSourcesUseCase
    @ObservationIgnored private let loadTimeline: (any LoadKnowledgeTimelineUseCase)?
    @ObservationIgnored private var graph = KnowledgeGraph.empty
    @ObservationIgnored private var knowledgeTimeline = KnowledgeTimeline.empty
    /// コミュニティ → 大きい順の番号（色と、まとまりの名前に使う）。
    @ObservationIgnored private var communityRanks: [Int: Int] = [:]

    public init(
        loadGraph: any LoadKnowledgeGraphUseCase,
        observeKnowledge: any ObserveKnowledgeUseCase,
        rebuildKnowledge: any RebuildKnowledgeUseCase,
        observeBuild: any ObserveKnowledgeBuildUseCase,
        findSources: any FindConceptSourcesUseCase,
        loadTimeline: (any LoadKnowledgeTimelineUseCase)? = nil
    ) {
        self.loadGraph = loadGraph
        self.observeKnowledge = observeKnowledge
        self.rebuildKnowledge = rebuildKnowledge
        self.observeBuild = observeBuild
        self.findSources = findSources
        self.loadTimeline = loadTimeline
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
            knowledgeTimeline = .empty
            applyGraph()
        } catch {
            state = .failed(message: error.message)
            return
        }
        // 育った順は後から読む（ノートの日時を調べるので、グラフを先に見せる）
        guard let loadTimeline, !graph.concepts.isEmpty,
            let timeline = try? await loadTimeline(for: graph), !timeline.notes.isEmpty
        else { return }
        knowledgeTimeline = timeline
        self.timeline = timeline.notes.map(TimelineStepItem.init)
        applyGraph()
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
        clearPath()
        guard let conceptID, let concept = graph.concepts.first(where: { $0.id == conceptID }) else {
            selected = nil
            return
        }
        let group = communityRanks[concept.community] ?? -1
        let related = graph.neighbors(of: conceptID).prefix(30).map(RelatedConceptItem.init)
        selected = ConceptDetailItem(concept: concept, group: group, related: Array(related), sources: [])
        let sources = (try? await findSources(concept: conceptID, in: graph)) ?? []
        guard selected?.id == conceptID else { return }
        selected = ConceptDetailItem(
            concept: concept, group: group, related: Array(related),
            sources: sources.prefix(30).map(ConceptSourceItem.init))
    }

    /// 概念がいちばん多く出てくるノートを開く（ダブルクリック）。
    public func openSource(of conceptID: Int) async {
        guard let first = try? await findSources(concept: conceptID, in: graph).first else { return }
        noteOpener?(first.chunk.notePath, first.chunk.line)
    }

    /// 検索の候補（名前の頭が一致するものを先に、重要な順）。
    public var searchSuggestions: [GraphNodeItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return nodes.filter { matchingNodeIDs.contains($0.id) }
            .sorted { first, second in
                let firstPrefix = first.label.lowercased().hasPrefix(query.lowercased())
                let secondPrefix = second.label.lowercased().hasPrefix(query.lowercased())
                return firstPrefix != secondPrefix ? firstPrefix : first.radius > second.radius
            }
            .prefix(8)
            .map(\.self)
    }

    // MARK: - 経路

    /// 選んでいる概念から `conceptID` までの、いちばん近い道をたどる（描いている線の中で）。
    public func findPath(to conceptID: Int) {
        guard let start = selected?.id, start != conceptID,
            let from = nodes.firstIndex(where: { $0.id == start }),
            let goal = nodes.firstIndex(where: { $0.id == conceptID })
        else { return }
        if let found = GraphPathFinder.path(from: from, to: goal, nodeCount: nodes.count, edges: edges) {
            path = found.map { PathStepItem(id: nodes[$0].id, label: nodes[$0].label, group: nodes[$0].group) }
            pathMessage = nil
        } else {
            path = []
            pathMessage = "「\(nodes[from].label)」から「\(nodes[goal].label)」へは、つながっていません"
        }
    }

    public func clearPath() {
        path = []
        pathMessage = nil
    }
}

extension GraphViewModel {
    // MARK: - 内部

    private func applyGraph() {
        let subgraph = graph.subgraph(limit: nodeLimit, edgeLimit: nodeLimit * 16)
        let maxRank = subgraph.concepts.map(\.pagerank).max() ?? 1
        let index = Dictionary(
            subgraph.concepts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sizes: [Int: Int] = [:]
        for concept in graph.concepts { sizes[concept.community, default: 0] += 1 }
        communityRanks = Dictionary(
            uniqueKeysWithValues: sizes.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.enumerated().map {
                ($1.key, $0)
            })
        nodes = subgraph.concepts.map { concept in
            GraphNodeItem(
                id: concept.id, label: concept.label,
                radius: 3 + 13 * (concept.pagerank / max(maxRank, .leastNonzeroMagnitude)).squareRoot(),
                community: concept.community, group: communityRanks[concept.community] ?? -1,
                birth: knowledgeTimeline.birth(of: concept.id))
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
                id: community, group: communityRanks[community] ?? -1, size: members.count,
                topLabels: members.sorted { $0.pagerank > $1.pagerank }.prefix(3).map(\.label))
        }
        .sorted { ($0.size, -$0.group) > ($1.size, -$1.group) }
        summary = "概念 \(graph.concepts.count)・関係 \(graph.relations.count)"
        updateMatches()
    }

    private func updateMatches() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        matchingNodeIDs =
            query.isEmpty ? [] : Set(nodes.filter { $0.label.localizedStandardContains(query) }.map(\.id))
    }
}
