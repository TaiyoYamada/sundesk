//
//  SwiftDataNoteIndexTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import SundeskMarkdown
import Testing

@Suite("SwiftDataNoteIndex")
struct SwiftDataNoteIndexTests {
    private func makeIndex() throws -> SwiftDataNoteIndex {
        SwiftDataNoteIndex(modelContainer: try NoteIndexStore.makeContainer(url: nil))
    }

    private func note(
        _ path: String,
        title: String,
        tags: [String] = [],
        links: [String] = [],
        body: String = "",
        stamp: String = "1"
    ) -> IndexedNote {
        IndexedNote(path: path, title: title, tags: tags, linkedPaths: links, body: body, stamp: stamp)
    }

    @Test("書き込んだノートの目印と、パスの目印を返す")
    func storesStampsAndSignature() async throws {
        let index = try makeIndex()
        #expect(try await index.pathSignature() == nil)

        try await index.apply(
            NoteIndexChanges(upserts: [note("a.md", title: "A", stamp: "s1")], removals: [], pathSignature: "sig")
        )

        #expect(try await index.stamps() == ["a.md": "s1"])
        #expect(try await index.pathSignature() == "sig")
    }

    @Test("同じパスは上書きし、リンクも入れ替える")
    func upsertReplacesLinks() async throws {
        let index = try makeIndex()
        try await index.apply(
            NoteIndexChanges(
                upserts: [
                    note("a.md", title: "A", links: ["b.md"]), note("b.md", title: "B"), note("c.md", title: "C"),
                ],
                removals: [],
                pathSignature: "1"
            )
        )

        try await index.apply(
            NoteIndexChanges(upserts: [note("a.md", title: "A2", links: ["c.md"])], removals: [], pathSignature: "1")
        )

        #expect(try await index.backlinks(to: "b.md").isEmpty)
        #expect(try await index.backlinks(to: "c.md") == [NoteSummary(path: "a.md", title: "A2")])
    }

    @Test("消したノートは、そのノートから出るリンクも消える")
    func removalDeletesOutgoingLinks() async throws {
        let index = try makeIndex()
        try await index.apply(
            NoteIndexChanges(
                upserts: [note("a.md", title: "A", links: ["b.md"]), note("b.md", title: "B")], removals: [],
                pathSignature: "1")
        )

        try await index.apply(NoteIndexChanges(upserts: [], removals: ["a.md"], pathSignature: "2"))

        #expect(try await index.stamps().keys.sorted() == ["b.md"])
        #expect(try await index.backlinks(to: "b.md").isEmpty)
    }

    @Test("検索はタイトルに一致したものを先に出し、本文の一致箇所を抜き出す")
    func searchRanksTitleFirst() async throws {
        let index = try makeIndex()
        try await index.apply(
            NoteIndexChanges(
                upserts: [
                    note("a.md", title: "行列の対角化", body: "固有値を並べた対角行列を使う。"),
                    note("b.md", title: "固有値・固有状態", body: "測定の理論。"),
                    note("c.md", title: "ベクトル", body: "関係なし"),
                ],
                removals: [],
                pathSignature: "1"
            )
        )

        let results = try await index.search("固有値", limit: 10)

        #expect(results.map(\.path) == ["b.md", "a.md"])
        #expect(results[1].snippet.contains("固有値を並べた"))
    }

    @Test("タグを数え、下位のタグも含めてノートを探す")
    func countsTagsAndFindsNotes() async throws {
        let index = try makeIndex()
        try await index.apply(
            NoteIndexChanges(
                upserts: [
                    note("a.md", title: "A", tags: ["量子計算", "研究/VQE"]),
                    note("b.md", title: "B", tags: ["量子計算"]),
                    note("c.md", title: "C", tags: ["研究"]),
                ],
                removals: [],
                pathSignature: "1"
            )
        )

        #expect(
            try await index.tags() == [
                TagCount(name: "量子計算", count: 2), TagCount(name: "研究", count: 1), TagCount(name: "研究/VQE", count: 1),
            ]
        )
        #expect(try await index.notes(taggedWith: "研究").map(\.path) == ["a.md", "c.md"])
    }

    @Test("書き込むと changes に流れる", .timeLimit(.minutes(1)))
    func notifiesChanges() async throws {
        let index = try makeIndex()
        var changes = index.changes().makeAsyncIterator()

        try await index.apply(NoteIndexChanges(upserts: [], removals: [], pathSignature: "1"))

        #expect(await changes.next() != nil)
    }
}

@Suite("研究ライブラリの見本を索引する（結合テスト）")
struct SampleLibraryIndexTests {
    private static let sampleLibrary = URL(filePath: #filePath)
        .deletingLastPathComponent()  // SundeskDataTests
        .deletingLastPathComponent()  // Core
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SundeskKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // sundesk
        .appending(path: "SampleLibrary", directoryHint: .isDirectory)

    @Test("すべてのノートを索引し、論文や実験へのリンクを題名でたどれる")
    func indexesSampleLibrary() async throws {
        let vault = FileSystemVaultRepository(root: { Self.sampleLibrary })
        let index = SwiftDataNoteIndex(modelContainer: try NoteIndexStore.makeContainer(url: nil))

        let summary = try await IndexVaultInteractor(vault: vault, index: index, markdown: SwiftMarkdownParser())()

        #expect(summary.total >= 25)
        #expect(summary.updated == summary.total)

        let paper = try await index.backlinks(to: "Papers/hansen2016-cma-es-tutorial/note.md").map(\.path)
        #expect(paper.contains("Notes/アイデア/VQE のパラメータを進化計算で最適化する.md"))
        #expect(paper.contains("Experiments/2026-09-10-vqe-h2-shots-spsa-cmaes/note.md"))
        let note = try await index.backlinks(to: "Notes/議事/2026-09-24 研究室ミーティング.md").map(\.path)
        #expect(note.contains("Notes/研究ログ/2026-09-29.md"))
        #expect(try await index.tags().contains { $0.name == "VQE" })

        // 2 回目は何も読み直さない
        #expect(
            try await IndexVaultInteractor(vault: vault, index: index, markdown: SwiftMarkdownParser())().updated == 0)
    }
}
