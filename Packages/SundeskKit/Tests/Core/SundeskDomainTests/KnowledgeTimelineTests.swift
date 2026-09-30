//
//  KnowledgeTimelineTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain
import Testing

@Suite("知識が育った順")
struct KnowledgeTimelineTests {
    private static func chunk(_ path: String, _ number: Int, title: String) -> NoteChunk {
        NoteChunk(
            id: "\(path)#\(number)", notePath: path, noteTitle: title, headingPath: [title], text: "本文",
            plainText: "本文", line: 1)
    }

    @Test("ノートを日時の順に並べ、概念ごとに初めて出てきたノートを覚える")
    func ordersNotesAndFindsFirstNote() {
        let mentions = [
            ConceptMention(concept: 1, chunk: "b.md#0", count: 2),
            ConceptMention(concept: 1, chunk: "a.md#3", count: 1),
            ConceptMention(concept: 2, chunk: "b.md#1", count: 1),
        ]
        let timeline = KnowledgeTimeline.make(
            mentions: mentions,
            notes: [
                "b.md": ("B", Date(timeIntervalSince1970: 200)), "a.md": ("A", Date(timeIntervalSince1970: 100)),
            ])

        #expect(timeline.notes.map(\.path) == ["a.md", "b.md"])
        #expect(timeline.firstNote == [1: 0, 2: 1])
        #expect(timeline.birth(of: 1) == 0)
        #expect(timeline.birth(of: 2) == 1)
        #expect(timeline.birth(of: 3) == nil)
    }

    @Test("同じ日時のノートはパスの順に並べる")
    func breaksTiesByPath() {
        let date = Date(timeIntervalSince1970: 100)
        let timeline = KnowledgeTimeline.make(mentions: [], notes: ["z.md": ("Z", date), "m.md": ("M", date)])

        #expect(timeline.notes.map(\.path) == ["m.md", "z.md"])
    }

    @Test("チャンクの ID からノートのパスを取り出す（パスに # があっても最後の # で切る）")
    func notePathOfChunk() {
        #expect(KnowledgeTimeline.notePath(ofChunk: "数学/固有値.md#4") == "数学/固有値.md")
        #expect(KnowledgeTimeline.notePath(ofChunk: "C#入門.md#0") == "C#入門.md")
        #expect(KnowledgeTimeline.notePath(ofChunk: "no-hash") == "no-hash")
    }

    @Test("ノートの日時は Vault から、題名は保存したチャンクから読む")
    func interactorReadsDatesAndTitles() async throws {
        let vault = VaultStub(files: ["a.md": "# A", "b.md": "# B"])
        await vault.touch("b.md", content: "# B\n追記")
        let repository = KnowledgeRepositorySpy()
        let chunks = [Self.chunk("a.md", 0, title: "ノート A"), Self.chunk("b.md", 0, title: "ノート B")]
        try await repository.replace(
            chunks: chunks.map { EmbeddedChunk(chunk: $0, contentHash: $0.id, embedding: nil) }, graph: .empty,
            embeddingModel: nil)
        let graph = KnowledgeGraph(
            concepts: [],
            relations: [],
            mentions: [
                ConceptMention(concept: 7, chunk: "b.md#0", count: 1),
                ConceptMention(concept: 8, chunk: "a.md#0", count: 1),
                ConceptMention(concept: 9, chunk: "gone.md#0", count: 1),
            ])

        let timeline = try await LoadKnowledgeTimelineInteractor(repository: repository, vault: vault)(for: graph)

        #expect(timeline.notes.map(\.title) == ["ノート A", "ノート B"])
        #expect(timeline.firstNote == [8: 0, 7: 1])
    }

    @Test("描く線の数は、指定がなければ概念の数の 4 倍まで、指定すればその数まで")
    func subgraphEdgeLimit() {
        let concepts = (0..<4).map {
            Concept(id: $0, label: "\($0)", normalized: "\($0)", score: 1, frequency: 1, pagerank: 1, community: 0)
        }
        var relations: [ConceptRelation] = []
        for source in 0..<4 {
            for target in (source + 1)..<4 {
                relations.append(
                    ConceptRelation(
                        source: source, target: target, kind: .cooccurrence, weight: Double(source + target),
                        evidence: nil))
            }
        }
        let graph = KnowledgeGraph(concepts: concepts, relations: relations, mentions: [])

        #expect(graph.subgraph(limit: 1).edges.isEmpty)
        #expect(graph.subgraph(limit: 4).edges.count == 6)
        #expect(graph.subgraph(limit: 4, edgeLimit: 2).edges.map(\.weight) == [5, 4])
    }
}
