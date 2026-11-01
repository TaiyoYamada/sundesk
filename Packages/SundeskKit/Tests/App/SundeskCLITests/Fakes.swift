//
//  Fakes.swift
//  SundeskCLITests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskData
import SundeskDomain

@testable import SundeskCLI

/// メモリの上の SwiftData と、本物の LibraryInteractor でできたライブラリ。通信と PDF の読み書きだけ偽物にする。
func makeAccess(metadata: [ReferenceIdentifier: ReferenceMetadata] = [:]) throws -> LibraryAccess {
    let library = LibraryInteractor(
        repository: try SwiftDataReferenceRepository.open(at: nil), attachments: StubAttachments(),
        bibliography: StubBibliography(metadata: metadata), pdfs: StubPDFReader())
    return LibraryAccess(library: library)
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
    func titleCandidates(in pdf: URL) -> [String] { [] }
    func pages(of pdf: URL) -> [String] { [] }
}
