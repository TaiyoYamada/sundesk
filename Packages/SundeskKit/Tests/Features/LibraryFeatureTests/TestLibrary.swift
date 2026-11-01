//
//  TestLibrary.swift
//  LibraryFeatureTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskData
import SundeskDomain
import Testing

@testable import LibraryFeature

/// メモリの上の SwiftData と、本物の LibraryInteractor でできたライブラリ。通信と PDF の読み書きだけ偽物にする。
@MainActor
struct TestLibrary {
    let library: LibraryInteractor
    let summarize: SummarizePaperInteractor

    init(metadata: [ReferenceIdentifier: ReferenceMetadata] = [:]) throws {
        let repository = try SwiftDataReferenceRepository.open(at: nil)
        library = LibraryInteractor(
            repository: repository, attachments: StubAttachments(), bibliography: StubBibliography(metadata: metadata),
            pdfs: StubPDFReader())
        summarize = SummarizePaperInteractor(
            summarizer: UnavailableSummarizer(), repository: repository, attachments: StubAttachments(),
            pdfs: StubPDFReader())
    }

    var dependencies: LibraryDependencies {
        LibraryDependencies(library: library, summarize: summarize)
    }
}

/// 条件が満たされるまで待つ（ViewModel が変更の知らせを受けて読み直すのを待つ）。
@MainActor
func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("2 秒待っても条件が満たされなかった", sourceLocation: sourceLocation)
}

struct StubAttachments: AttachmentStore {
    let root = URL(filePath: "/tmp/sundesk-stub-storage")

    func importPDF(_ source: URL, for referenceID: UUID) throws(LibraryError) -> String {
        "\(referenceID.uuidString)/\(source.lastPathComponent)"
    }

    func url(for path: String) -> URL { root.appending(path: path) }

    func removeAttachments(of referenceID: UUID) throws(LibraryError) {}
}

struct StubBibliography: BibliographyService {
    let metadata: [ReferenceIdentifier: ReferenceMetadata]

    func metadata(for identifier: ReferenceIdentifier) async throws(LibraryError) -> ReferenceMetadata {
        guard let found = metadata[identifier] else { throw .notFound(identifier.text) }
        return found
    }

    func search(_ query: String) async throws(LibraryError) -> [ReferenceMetadata] {
        []
    }

    func downloadPDF(arxiv: String) async throws(LibraryError) -> URL {
        URL(filePath: "/tmp/\(arxiv).pdf")
    }
}

struct StubPDFReader: PDFReading {
    func identifier(in pdf: URL) -> ReferenceIdentifier? { nil }
    func titleCandidates(in pdf: URL) -> [String] { ["PDF の題名"] }
    func pages(of pdf: URL) -> [String] { ["本文"] }
}

struct UnavailableSummarizer: PaperSummarizer {
    func unavailableReason() -> String? { "テストでは使わない" }
    func inputBudget() async -> Int { 0 }
    func tokenCount(_ text: String) async throws(SummaryError) -> Int { 0 }
    func notes(on part: String, title: String) async throws(SummaryError) -> String { "" }
    func summary(from notes: String, title: String) async throws(SummaryError) -> PaperSummary {
        throw .unavailable("テストでは使わない")
    }
}
