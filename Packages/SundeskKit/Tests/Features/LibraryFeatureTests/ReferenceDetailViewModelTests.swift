//
//  ReferenceDetailViewModelTests.swift
//  LibraryFeatureTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import CoreGraphics
import Foundation
import SundeskDomain
import Testing

@testable import LibraryFeature

@MainActor
@Suite("文献の詳細と PDF を読む画面")
struct ReferenceDetailViewModelTests {
    @Test("編集は少し待ってから保存し、一覧にも出る")
    func editingSaves() async throws {
        let test = try TestLibrary()
        let reference = try await test.library.addBlank(into: nil)
        let detail = test.dependencies.makeDetail(reference.id)
        let watching = Task { await detail.start() }
        defer { watching.cancel() }
        await waitUntil { detail.draft != nil }

        detail.draft?.title = "変分量子固有値ソルバー"
        detail.draft?.authors = "Peruzzo, Alberto\nJarrod McClean"
        detail.draft?.date = "2014-07"
        detail.addTag("VQE")
        detail.addTag("VQE")
        await detail.flush()

        let saved = try #require(try await test.library.reference(reference.id))
        #expect(saved.metadata.title == "変分量子固有値ソルバー")
        let authors = [Creator(family: "Peruzzo", given: "Alberto"), Creator(family: "McClean", given: "Jarrod")]
        #expect(saved.metadata.authors == authors)
        #expect(saved.metadata.issued == PartialDate(year: 2014, month: 7))
        #expect(saved.tags == ["VQE"])
    }

    @Test("ほかの場所で書き換わると、画面の値を読み直す")
    func reloadsExternalChanges() async throws {
        let test = try TestLibrary()
        var reference = try await test.library.addBlank(into: nil)
        let detail = test.dependencies.makeDetail(reference.id)
        let watching = Task { await detail.start() }
        defer { watching.cancel() }
        await waitUntil { detail.draft != nil }

        reference.note = "ほかのウインドウで書いたメモ"
        try await test.library.save(reference)

        await waitUntil { detail.draft?.note == "ほかのウインドウで書いたメモ" }
    }

    @Test("要約できないときは、理由を出す")
    func summaryUnavailable() async throws {
        let test = try TestLibrary()
        let reference = try await test.library.addBlank(into: nil)
        let detail = test.dependencies.makeDetail(reference.id)

        await detail.makeSummary()

        #expect(detail.summaryState == .failed("要約できません: テストでは使わない"))
    }

    @Test("ハイライトを足してコメントを書き、メモに引用する")
    func highlights() async throws {
        let test = try TestLibrary()
        let reference = try await test.library.addBlank(into: nil)
        let reader = test.dependencies.makeReader(reference.id)
        let watching = Task { await reader.start() }
        let watchingDetail = Task { await reader.detail.start() }
        defer {
            watching.cancel()
            watchingDetail.cancel()
        }
        await waitUntil { reader.detail.draft != nil }

        reader.color = .green
        let rect = HighlightRect(pageIndex: 2, rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        await reader.addHighlight(text: "We propose VQE.", rects: [rect])
        await waitUntil { reader.highlights.count == 1 }
        let highlight = try #require(reader.highlights.first)
        #expect(highlight.color == .green)
        #expect(highlight.pageLabel == "p. 3")
        #expect(reader.selectedHighlightID == highlight.id)

        reader.setComment("大事", for: highlight.id)
        await waitUntil { reader.highlights.first?.comment == "大事" }
        reader.appendToNote(highlight.id)
        #expect(reader.detail.draft?.note == "> We propose VQE.\n> （p. 3）\n\n大事")

        await reader.deleteHighlight(highlight.id)
        await waitUntil { reader.highlights.isEmpty }
    }
}
