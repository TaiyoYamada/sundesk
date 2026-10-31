//
//  SwiftDataReferenceRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain
import Testing

@testable import SundeskData

@Suite("SwiftData の保存")
struct SwiftDataReferenceRepositoryTests {
    private let repository: SwiftDataReferenceRepository

    init() throws {
        repository = try SwiftDataReferenceRepository.open(at: nil)
    }

    @Test("文献を保存して読み戻すと、すべての項目が残る")
    func roundTrip() async throws {
        let collection = ReferenceCollection(name: "研究")
        try await repository.save(collection)
        let reference = Reference(
            metadata: ReferenceMetadata(
                type: .conferencePaper, title: "題名", authors: [Creator(family: "山田", given: "大陽")],
                issued: PartialDate(year: 2026, month: 11), containerTitle: "会議", volume: "1", issue: "2",
                pages: "3-4", publisher: "出版社", doi: "10.1/x", arxiv: "2101.00001", isbn: "9780262035613",
                url: "https://example.com", abstract: "要旨"),
            citationKey: "key", tags: ["a", "b"], collectionIDs: [collection.id], readingStatus: .reading,
            note: "# メモ", attachment: "id/paper.pdf",
            summary: PaperSummary(purpose: "目的", method: "手法", results: "結果", limitations: "限界"),
            dateAdded: Date(timeIntervalSince1970: 100), dateModified: Date(timeIntervalSince1970: 200))

        try await repository.save(reference)

        #expect(try await repository.reference(reference.id) == reference)
        #expect(try await repository.references() == [reference])
    }

    @Test("書き直すと、同じ文献が更新される")
    func update() async throws {
        var reference = Reference(metadata: ReferenceMetadata(title: "前"))
        try await repository.save(reference)
        reference.metadata.title = "後"
        try await repository.save(reference)

        #expect(try await repository.references().map(\.metadata.title) == ["後"])
    }

    @Test("コレクションを消すと、中のコレクションも消え、文献からも外れる")
    func deleteCollection() async throws {
        let parent = ReferenceCollection(name: "研究")
        let child = ReferenceCollection(name: "最適化", parentID: parent.id)
        try await repository.save(parent)
        try await repository.save(child)
        let reference = Reference(metadata: ReferenceMetadata(title: "T"), collectionIDs: [child.id])
        try await repository.save(reference)

        try await repository.deleteCollection(parent.id)

        #expect(try await repository.collections().isEmpty)
        #expect(try await repository.reference(reference.id)?.collectionIDs == [])
    }

    @Test("注釈はページ順に並び、文献を消すと一緒に消える")
    func annotations() async throws {
        let reference = Reference(metadata: ReferenceMetadata(title: "T"))
        try await repository.save(reference)
        let later = Annotation(
            referenceID: reference.id, color: .red, text: "後",
            rects: [AnnotationRect(pageIndex: 3, x: 1, y: 2, width: 3, height: 4)])
        let earlier = Annotation(
            referenceID: reference.id, color: .yellow, text: "前", comment: "コメント",
            rects: [AnnotationRect(pageIndex: 0, x: 1, y: 2, width: 3, height: 4)])
        try await repository.save(later)
        try await repository.save(earlier)

        let stored = try await repository.annotations(of: reference.id)
        #expect(stored.map(\.text) == ["前", "後"])
        #expect(stored.first == earlier)

        try await repository.deleteReferences([reference.id])
        #expect(try await repository.annotations(of: reference.id).isEmpty)
        #expect(try await repository.references().isEmpty)
    }

    @Test("書き換えるたびに知らせる")
    func changes() async throws {
        let stream = await repository.changes()
        try await repository.save(Reference(metadata: ReferenceMetadata(title: "T")))

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}
