//
//  KnowledgeUseCaseTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import Testing

@Suite("知識の作り直し")
struct KnowledgeBuilderTests {
    private func makeBuilder(
        vault: VaultStub, engine: KnowledgeEngineSpy, repository: KnowledgeRepositorySpy
    ) -> KnowledgeBuilder {
        KnowledgeBuilder(
            vault: vault, markdown: MarkdownParserStub(), chunker: ChunkerStub(), engine: engine,
            repository: repository,
            batchSize: 2)
    }

    @Test("ノートを区切り、埋め込み、グラフを作って保存する。リンクは解決してから渡す")
    func buildsEverything() async throws {
        let vault = VaultStub(files: [
            "数学/固有値.md": "# 固有値\n[[線形代数]] の話", "数学/線形代数.md": "# 線形代数\n本文", "図.png": "",
        ])
        let engine = KnowledgeEngineSpy()
        let repository = KnowledgeRepositorySpy()

        try await makeBuilder(vault: vault, engine: engine, repository: repository).rebuild()

        let notes = await engine.graphNotes
        #expect(notes.map(\.path).sorted() == ["数学/固有値.md", "数学/線形代数.md"])
        #expect(notes.first { $0.path == "数学/固有値.md" }?.links == ["数学/線形代数.md"])
        #expect(notes.first { $0.path == "数学/固有値.md" }?.title == "固有値")
        let saved = await repository.saved
        #expect(saved.count == 2)
        #expect(saved.allSatisfy { $0.embedding != nil })
        #expect(await repository.model == "テスト用")
        #expect(await repository.savedGraph?.concepts.count == 1)
    }

    @Test("本文が変わっていないチャンクは、前回の埋め込みを使い回す")
    func reusesEmbeddings() async throws {
        let vault = VaultStub(files: ["a.md": "# A\n本文", "b.md": "# B\n本文"])
        let engine = KnowledgeEngineSpy()
        let repository = KnowledgeRepositorySpy()
        let builder = makeBuilder(vault: vault, engine: engine, repository: repository)
        try await builder.rebuild()
        let firstCount = await engine.embeddedDocuments

        await vault.touch("b.md", content: "# B\n書き換えた")
        try await builder.rebuild()

        #expect(firstCount == 2)
        #expect(await engine.embeddedDocuments == 3)
    }

    @Test("エンジンが失敗したら、保存せずに失敗を返す")
    func propagatesEngineFailure() async {
        let vault = VaultStub(files: ["a.md": "# A"])
        let engine = KnowledgeEngineSpy(failure: .engine("エンジンが止まっています"))
        let repository = KnowledgeRepositorySpy()

        await #expect(throws: KnowledgeError.engine("エンジンが止まっています")) {
            try await makeBuilder(vault: vault, engine: engine, repository: repository).rebuild()
        }
        #expect(await repository.saved.isEmpty)
    }

    @Test("進み具合を流し、終わったら件数を知らせる（途中は最新のものだけ届く）")
    func reportsProgress() async throws {
        let vault = VaultStub(files: ["a.md": "# A", "b.md": "# B", "c.md": "# C"])
        let builder = makeBuilder(vault: vault, engine: KnowledgeEngineSpy(), repository: KnowledgeRepositorySpy())
        let steps = await builder.progress()
        let collected = Task {
            var result: [KnowledgeBuildStep?] = []
            for await step in steps {
                result.append(step)
                if case .finished = step { break }
            }
            return result
        }

        try await builder.rebuild()

        let result = await collected.value
        #expect(result.first == .some(nil))
        #expect(result.last == .finished(concepts: 1, relations: 1, chunks: 3))
    }
}

@Suite("知識グラフの形")
struct KnowledgeGraphTests {
    private let graph = KnowledgeGraph(
        concepts: [
            Concept(id: 0, label: "固有値", normalized: "固有値", score: 1, frequency: 3, pagerank: 0.5, community: 0),
            Concept(id: 1, label: "固有ベクトル", normalized: "固有ベクトル", score: 1, frequency: 2, pagerank: 0.3, community: 0),
            Concept(id: 2, label: "行列", normalized: "行列", score: 1, frequency: 5, pagerank: 0.2, community: 1),
        ],
        relations: [
            ConceptRelation(source: 0, target: 1, kind: .cooccurrence, weight: 1, evidence: nil),
            ConceptRelation(source: 1, target: 0, kind: .definition, weight: 2, evidence: nil),
            ConceptRelation(source: 0, target: 2, kind: .isA, weight: 0.5, evidence: nil),
        ],
        mentions: []
    )

    @Test("隣の概念は、同じ組の線をまとめて、重みの大きい順に並べる")
    func neighbors() {
        let neighbors = graph.neighbors(of: 0)

        #expect(neighbors.map(\.concept.label) == ["固有ベクトル", "行列"])
        #expect(neighbors[0].kinds == [.cooccurrence, .definition])
        #expect(neighbors[0].weight == 3)
    }

    @Test("重要な概念だけを取り出し、その間の線だけを残す")
    func subgraph() {
        let subgraph = graph.subgraph(limit: 2)

        #expect(subgraph.concepts.map(\.id) == [0, 1])
        #expect(subgraph.edges.count == 1)
        #expect(subgraph.edges.first?.weight == 3)
    }
}

// MARK: - テスト用の偽物

struct ChunkerStub: NoteChunking {
    func chunks(for source: String, path: String, title: String) -> [NoteChunk] {
        [
            NoteChunk(
                id: "\(path)#0", notePath: path, noteTitle: title, headingPath: [title], text: source,
                plainText: source, line: 1)
        ]
    }
}

actor KnowledgeEngineSpy: KnowledgeEngine {
    private(set) var graphNotes: [GraphSourceNote] = []
    private(set) var embeddedDocuments = 0
    private let failure: KnowledgeError?

    init(failure: KnowledgeError? = nil) {
        self.failure = failure
    }

    func embed(_ texts: [String], kind: EmbeddingKind) async throws(KnowledgeError) -> EmbeddingBatch {
        if let failure { throw failure }
        if kind == .document { embeddedDocuments += texts.count }
        return EmbeddingBatch(model: "テスト用", vectors: texts.map { [Float($0.count), 1] })
    }

    func buildGraph(notes: [GraphSourceNote], similarity: Bool) async throws(KnowledgeError) -> KnowledgeGraph {
        graphNotes = notes
        return KnowledgeGraph(
            concepts: [Concept(id: 0, label: "A", normalized: "a", score: 1, frequency: 1, pagerank: 1, community: 0)],
            relations: [ConceptRelation(source: 0, target: 0, kind: .link, weight: 1, evidence: nil)],
            mentions: [])
    }
}

actor KnowledgeRepositorySpy: KnowledgeRepository {
    private(set) var saved: [EmbeddedChunk] = []
    private(set) var savedGraph: KnowledgeGraph?
    private(set) var model: String?

    func replace(chunks: [EmbeddedChunk], graph: KnowledgeGraph, embeddingModel: String?) async throws(KnowledgeError) {
        saved = chunks
        savedGraph = graph
        model = embeddingModel
    }

    func graph() async throws(KnowledgeError) -> KnowledgeGraph { savedGraph ?? .empty }

    func allChunks() async throws(KnowledgeError) -> [NoteChunk] { saved.map(\.chunk) }

    func chunks(ids: [String]) async throws(KnowledgeError) -> [NoteChunk] {
        saved.map(\.chunk).filter { ids.contains($0.id) }
    }

    func storedEmbeddings(model: String) async throws(KnowledgeError) -> [String: [Float]] {
        guard model == self.model else { return [:] }
        return Dictionary(
            saved.compactMap { item in item.embedding.map { (item.contentHash, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    func nearestChunks(to vector: [Float], limit: Int) async throws(KnowledgeError) -> [ScoredChunk] { [] }

    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
