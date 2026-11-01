//
//  SummarizePaperInteractorTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import Testing

@testable import SundeskDomain

/// 文字数をトークン数とみなし、渡された文を覚えておく要約器。
actor FakeSummarizer: PaperSummarizer {
    private(set) var notedParts: [String] = []
    private(set) var combined: String?
    nonisolated let reason: String?
    nonisolated let budget: Int

    init(reason: String? = nil, budget: Int = 10) {
        self.reason = reason
        self.budget = budget
    }

    nonisolated func unavailableReason() -> String? { reason }

    func inputBudget() async -> Int { budget }

    func tokenCount(_ text: String) async throws(SummaryError) -> Int { text.count }

    func notes(on part: String, title: String) async throws(SummaryError) -> String {
        notedParts.append(part)
        return "m\(notedParts.count)"
    }

    func summary(from notes: String, title: String) async throws(SummaryError) -> PaperSummary {
        combined = notes
        return PaperSummary(purpose: "目的", method: "手法", results: "結果", limitations: "限界")
    }
}

@Suite("論文の要約")
struct SummarizePaperInteractorTests {
    private let repository = InMemoryReferenceRepository()

    private func run(
        _ summarizer: FakeSummarizer, pages: [String], attachment: String? = "a/paper.pdf"
    ) async throws -> (progress: [SummaryProgress], reference: Reference?) {
        let reference = Reference(metadata: ReferenceMetadata(title: "T"), attachment: attachment)
        await repository.save(reference)
        let interactor = SummarizePaperInteractor(
            summarizer: summarizer, repository: repository, attachments: FakeAttachmentStore(),
            pdfs: FakePDFReader(pages: pages))
        var progress: [SummaryProgress] = []
        for try await event in interactor(reference.id) { progress.append(event) }
        return (progress, await repository.reference(reference.id))
    }

    @Test("区切って読み、メモをまとめて要約にし、文献に保存する")
    func summarize() async throws {
        let summarizer = FakeSummarizer()
        let result = try await run(summarizer, pages: ["aaaaaa", "bbbbbb", "References\nzzz"])

        #expect(await summarizer.notedParts == ["aaaaaa", "bbbbbb"])
        #expect(await summarizer.combined == "m1\n\nm2")
        #expect(result.progress.prefix(3) == [.reading(part: 1, count: 2), .reading(part: 2, count: 2), .combining])
        #expect(result.reference?.summary?.purpose == "目的")
    }

    @Test("使えないときと、PDF がないときは失敗する")
    func failures() async {
        await #expect(throws: SummaryError.unavailable("理由")) {
            try await run(FakeSummarizer(reason: "理由"), pages: ["本文"])
        }
        await #expect(throws: SummaryError.noText) {
            try await run(FakeSummarizer(), pages: ["本文"], attachment: nil)
        }
        await #expect(throws: SummaryError.noText) {
            try await run(FakeSummarizer(), pages: ["", "  "])
        }
    }
}
