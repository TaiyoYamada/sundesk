//
//  GraphViewModelTests.swift
//  GraphFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import GraphFeature
import SundeskDomain
import Testing

@MainActor
@Suite("GraphViewModel")
struct GraphViewModelTests {
    private static let graph = KnowledgeGraph(
        concepts: [
            Concept(id: 0, label: "固有値", normalized: "固有値", score: 3, frequency: 5, pagerank: 0.5, community: 0),
            Concept(id: 1, label: "固有ベクトル", normalized: "固有ベクトル", score: 2, frequency: 3, pagerank: 0.3, community: 0),
            Concept(id: 2, label: "量子ビット", normalized: "量子ビット", score: 2, frequency: 2, pagerank: 0.2, community: 1),
        ],
        relations: [
            ConceptRelation(source: 0, target: 1, kind: .definition, weight: 2, evidence: "a.md#0"),
            ConceptRelation(source: 1, target: 2, kind: .cooccurrence, weight: 1, evidence: "a.md#0"),
        ],
        mentions: [ConceptMention(concept: 0, chunk: "a.md#0", count: 4)]
    )

    private func makeViewModel(graph: KnowledgeGraph = graph, rebuildFailure: KnowledgeError? = nil) -> GraphViewModel {
        GraphViewModel(
            loadGraph: GraphStub(graph: graph), observeKnowledge: GraphStub(graph: graph),
            rebuildKnowledge: RebuildStub(failure: rebuildFailure), observeBuild: RebuildStub(failure: nil),
            findSources: GraphStub(graph: graph))
    }

    @Test("知識がなければ空、あれば点と線と分野を出す")
    func loadsGraph() async {
        let empty = makeViewModel(graph: .empty)
        await empty.load()
        #expect(empty.state == .empty)

        let viewModel = makeViewModel()
        await viewModel.load()

        #expect(viewModel.state == .ready)
        #expect(viewModel.nodes.map(\.label) == ["固有値", "固有ベクトル", "量子ビット"])
        #expect(viewModel.nodes[0].radius > viewModel.nodes[2].radius)
        #expect(viewModel.edges.count == 2)
        #expect(viewModel.communities.map(\.id) == [0, 1])
        #expect(viewModel.summary == "概念 3・関係 2")
    }

    @Test("検索に一致した概念を目立たせる")
    func searchHighlightsMatches() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.searchText = "固有"

        #expect(viewModel.matchingNodeIDs == [0, 1])
    }

    @Test("概念を選ぶと、隣の概念と出どころを出す")
    func selectShowsDetail() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        await viewModel.select(conceptID: 0)

        #expect(viewModel.selected?.label == "固有値")
        #expect(viewModel.selected?.related.map(\.label) == ["固有ベクトル"])
        #expect(viewModel.selected?.related.first?.kinds == "定義")
        #expect(viewModel.selected?.sources.map(\.path) == ["数学/固有値.md"])
        #expect(viewModel.selected?.sources.first?.heading == "定義")
        await viewModel.select(conceptID: nil)
        #expect(viewModel.selected == nil)
    }

    @Test("作り直しに失敗したらメッセージを出す")
    func rebuildFailure() async {
        let viewModel = makeViewModel(rebuildFailure: .engine("エンジンを起動できませんでした"))

        await viewModel.rebuild()

        #expect(viewModel.buildError == "エンジンを起動できませんでした")
    }
}

private struct GraphStub: LoadKnowledgeGraphUseCase, ObserveKnowledgeUseCase, FindConceptSourcesUseCase {
    let graph: KnowledgeGraph

    func callAsFunction() async throws(KnowledgeError) -> KnowledgeGraph { graph }

    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func callAsFunction(concept: Int, in graph: KnowledgeGraph) async throws(KnowledgeError) -> [ConceptSource] {
        [
            ConceptSource(
                chunk: NoteChunk(
                    id: "a.md#0", notePath: "数学/固有値.md", noteTitle: "固有値", headingPath: ["固有値", "定義"],
                    text: "固有値とは", plainText: "固有値とは", line: 5),
                count: 4)
        ]
    }
}

private struct RebuildStub: RebuildKnowledgeUseCase, ObserveKnowledgeBuildUseCase {
    let failure: KnowledgeError?

    func callAsFunction() async throws(KnowledgeError) {
        if let failure { throw failure }
    }

    func callAsFunction() async -> AsyncStream<KnowledgeBuildStep?> { AsyncStream { $0.finish() } }
}
