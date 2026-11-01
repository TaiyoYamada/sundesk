//
//  SummarizePaperUseCase.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 文献の PDF を要約し、文献に保存する。
public protocol SummarizePaperUseCase: Sendable {
    func callAsFunction(_ referenceID: UUID) -> AsyncThrowingStream<SummaryProgress, any Error>
}

public struct SummarizePaperInteractor: SummarizePaperUseCase {
    private let summarizer: any PaperSummarizer
    private let repository: any ReferenceRepository
    private let attachments: any AttachmentStore
    private let pdfs: any PDFReading

    public init(
        summarizer: any PaperSummarizer, repository: any ReferenceRepository, attachments: any AttachmentStore,
        pdfs: any PDFReading
    ) {
        self.summarizer = summarizer
        self.repository = repository
        self.attachments = attachments
        self.pdfs = pdfs
    }

    public func callAsFunction(_ referenceID: UUID) -> AsyncThrowingStream<SummaryProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let summary = try await summarize(referenceID) { continuation.yield($0) }
                    continuation.yield(.finished(summary))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func summarize(
        _ referenceID: UUID, progress: (SummaryProgress) -> Void
    ) async throws -> PaperSummary {
        if let reason = summarizer.unavailableReason() { throw SummaryError.unavailable(reason) }
        guard let reference = try await repository.reference(referenceID), let path = reference.attachment else {
            throw SummaryError.noText
        }
        let pages = PaperText.body(of: pdfs.pages(of: attachments.url(for: path)))
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw SummaryError.noText
        }

        let title = reference.metadata.title
        let budget = await summarizer.inputBudget()
        let parts = try await PaperText.parts(of: pages, budget: budget, tokenCount: summarizer.tokenCount)
        var notes: [String] = []
        for (index, part) in parts.enumerated() {
            progress(.reading(part: index + 1, count: parts.count))
            notes.append(try await summarizer.notes(on: part, title: title))
        }

        progress(.combining)
        // メモを合わせても上限を超えるときは、メモをさらにまとめる
        while notes.count > 1, try await summarizer.tokenCount(notes.joined(separator: "\n\n")) > budget {
            var merged: [String] = []
            for group in try await PaperText.parts(of: notes, budget: budget, tokenCount: summarizer.tokenCount) {
                merged.append(try await summarizer.notes(on: group, title: title))
            }
            notes = merged
        }
        let summary = try await summarizer.summary(from: notes.joined(separator: "\n\n"), title: title)

        // 要約している間にメモなどが書き換わっていることがあるので、読み直してから書く
        if var latest = try await repository.reference(referenceID) {
            latest.summary = summary
            try await repository.save(latest)
        }
        return summary
    }
}
