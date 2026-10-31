//
//  Fakes.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

@testable import SundeskDomain

/// メモリの上だけの保存先。
actor InMemoryReferenceRepository: ReferenceRepository {
    private(set) var stored: [UUID: Reference] = [:]
    private var collectionsByID: [UUID: ReferenceCollection] = [:]
    private var annotationsByID: [UUID: Annotation] = [:]

    func references() -> [Reference] {
        stored.values.sorted { $0.dateAdded < $1.dateAdded }
    }

    func reference(_ id: UUID) -> Reference? {
        stored[id]
    }

    func save(_ reference: Reference) {
        stored[reference.id] = reference
    }

    func deleteReferences(_ ids: [UUID]) {
        for id in ids { stored[id] = nil }
    }

    func collections() -> [ReferenceCollection] {
        Array(collectionsByID.values)
    }

    func save(_ collection: ReferenceCollection) {
        collectionsByID[collection.id] = collection
    }

    func deleteCollection(_ id: UUID) {
        collectionsByID[id] = nil
    }

    func annotations(of referenceID: UUID) -> [Annotation] {
        annotationsByID.values.filter { $0.referenceID == referenceID }
    }

    func save(_ annotation: Annotation) {
        annotationsByID[annotation.id] = annotation
    }

    func deleteAnnotation(_ id: UUID) {
        annotationsByID[id] = nil
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

/// 写したパスを覚えるだけの添付の置き場。
final class FakeAttachmentStore: AttachmentStore, @unchecked Sendable {
    let root = URL(filePath: "/tmp/sundesk-fake-storage")
    private(set) var imported: [UUID: URL] = [:]
    private(set) var removed: [UUID] = []

    func importPDF(_ source: URL, for referenceID: UUID) throws(LibraryError) -> String {
        imported[referenceID] = source
        return "\(referenceID.uuidString)/\(source.lastPathComponent)"
    }

    func url(for path: String) -> URL {
        root.appending(path: path)
    }

    func removeAttachments(of referenceID: UUID) throws(LibraryError) {
        removed.append(referenceID)
    }
}

/// 決まった書誌情報を返す。
struct FakeBibliography: BibliographyService {
    var metadata: [ReferenceIdentifier: ReferenceMetadata] = [:]

    func metadata(for identifier: ReferenceIdentifier) async throws(LibraryError) -> ReferenceMetadata {
        guard let found = metadata[identifier] else { throw .notFound(identifier.text) }
        return found
    }

    func downloadPDF(arxiv: String) async throws(LibraryError) -> URL {
        URL(filePath: "/tmp/\(arxiv).pdf")
    }
}

/// 決まった中身を返す PDF の読み手。
struct FakePDFReader: PDFReading {
    var identifier: ReferenceIdentifier?
    var title: String?
    var pages: [String] = ["本文"]

    func identifier(in pdf: URL) -> ReferenceIdentifier? { identifier }
    func title(in pdf: URL) -> String? { title }
    func pages(of pdf: URL) -> [String] { pages }
}
