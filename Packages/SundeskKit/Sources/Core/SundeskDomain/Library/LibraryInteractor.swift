//
//  LibraryInteractor.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

public struct LibraryInteractor: ManageLibraryUseCase {
    private let repository: any ReferenceRepository
    private let attachments: any AttachmentStore
    private let bibliography: any BibliographyService
    private let pdfs: any PDFReading

    public init(
        repository: any ReferenceRepository, attachments: any AttachmentStore,
        bibliography: any BibliographyService, pdfs: any PDFReading
    ) {
        self.repository = repository
        self.attachments = attachments
        self.bibliography = bibliography
        self.pdfs = pdfs
    }

    public func references() async throws(LibraryError) -> [Reference] {
        try await repository.references()
    }

    public func reference(_ id: UUID) async throws(LibraryError) -> Reference? {
        try await repository.reference(id)
    }

    public func collections() async throws(LibraryError) -> [ReferenceCollection] {
        try await repository.collections()
    }

    public func changes() async -> AsyncStream<Void> {
        await repository.changes()
    }

    // MARK: - 文献

    public func add(
        _ identifier: ReferenceIdentifier, into collectionID: UUID?
    ) async throws(LibraryError) -> Reference {
        let all = try await repository.references()
        if let existing = all.first(where: { $0.metadata.matches(identifier) }) { return existing }

        let metadata = try await bibliography.metadata(for: identifier)
        let reference = try await create(metadata, into: collectionID, existing: all)
        if case .arxiv(let id) = identifier {
            let pdf = try await bibliography.downloadPDF(arxiv: id)
            try await attachPDF(pdf, to: reference.id)
            try? FileManager.default.removeItem(at: pdf)
        }
        return try await repository.reference(reference.id) ?? reference
    }

    public func importPDF(_ url: URL, into collectionID: UUID?) async throws(LibraryError) -> Reference {
        guard !pdfs.pages(of: url).isEmpty else { throw .unreadablePDF }
        let all = try await repository.references()
        if let identifier = pdfs.identifier(in: url),
            let existing = all.first(where: { $0.metadata.matches(identifier) })
        {
            if existing.attachment == nil { try await attachPDF(url, to: existing.id) }
            return try await repository.reference(existing.id) ?? existing
        }

        // 書誌情報が見つからなくても、PDF の題名で足しておく（あとで手で直せる）
        let metadata = await identify(url) ?? fallbackMetadata(of: url)
        let reference = try await create(metadata, into: collectionID, existing: all)
        try await attachPDF(url, to: reference.id)
        return try await repository.reference(reference.id) ?? reference
    }

    public func addBlank(into collectionID: UUID?) async throws(LibraryError) -> Reference {
        let reference = Reference(
            metadata: ReferenceMetadata(title: "無題"), collectionIDs: collectionID.map { [$0] } ?? [])
        try await repository.save(reference)
        return reference
    }

    public func attachPDF(_ url: URL, to referenceID: UUID) async throws(LibraryError) {
        guard var reference = try await repository.reference(referenceID) else { return }
        try attachments.removeAttachments(of: referenceID)
        reference.attachment = try attachments.importPDF(url, for: referenceID)
        try await save(reference)
    }

    public func save(_ reference: Reference) async throws(LibraryError) {
        var reference = reference
        reference.dateModified = .now
        if reference.citationKey.isEmpty {
            let keys = Set(try await repository.references().filter { $0.id != reference.id }.map(\.citationKey))
            reference.citationKey = CitationKey.make(for: reference.metadata, existing: keys)
        }
        try await repository.save(reference)
    }

    public func refreshMetadata(of referenceID: UUID) async throws(LibraryError) {
        guard var reference = try await repository.reference(referenceID) else { return }
        let metadata = reference.metadata
        let identifier =
            [metadata.doi, metadata.arxiv, metadata.isbn].lazy.compactMap(ReferenceIdentifier.init(parsing:)).first
        if let identifier {
            try await replaceMetadata(of: &reference, with: try await bibliography.metadata(for: identifier))
        } else if let pdf = pdfURL(of: reference), let found = await identify(pdf) {
            try await replaceMetadata(of: &reference, with: found)
        } else {
            throw .notFound("「\(metadata.title)」")
        }
        try await save(reference)
    }

    public func findMissingMetadata(
        progress: @Sendable (Int, Int) async -> Void
    ) async throws(LibraryError) -> (found: Int, total: Int) {
        let targets = try await repository.references().filter { reference in
            let metadata = reference.metadata
            return reference.attachment != nil && metadata.doi.isEmpty && metadata.arxiv.isEmpty
                && metadata.isbn.isEmpty
        }
        var found = 0
        for (index, target) in targets.enumerated() {
            await progress(index + 1, targets.count)
            guard var reference = try await repository.reference(target.id), let pdf = pdfURL(of: reference)
            else { continue }
            if let metadata = await identify(pdf) {
                try await replaceMetadata(of: &reference, with: metadata)
                found += 1
            } else if reference.metadata.type == .document {
                // 書誌情報を探せず、PDF とファイル名から拾ったままの文献だけ、拾い直す（種類を変えた文献は手で直したとみなして残す）
                try await replaceMetadata(of: &reference, with: fallbackMetadata(of: pdf))
            } else {
                continue
            }
            try await save(reference)
        }
        return (found, targets.count)
    }

    /// 書誌情報を差し替える。引用キーが前の書誌情報から自動で付けたままなら、新しい書誌情報で付け直す（手で変えたキーは残す）。
    private func replaceMetadata(
        of reference: inout Reference, with metadata: ReferenceMetadata
    ) async throws(LibraryError) {
        let id = reference.id
        let keys = Set(try await repository.references().filter { $0.id != id }.map(\.citationKey))
        if reference.citationKey == CitationKey.make(for: reference.metadata, existing: keys) {
            reference.citationKey = CitationKey.make(for: metadata, existing: keys)
        }
        reference.metadata = metadata
    }

    /// PDF の DOI か arXiv の ID、題名の候補、ファイル名の順に、書誌情報を探す。
    /// どの段でも、ファイル名の年と筆頭著者に食い違うものは採らない。
    private func identify(_ pdf: URL) async -> ReferenceMetadata? {
        let hint = FileNameHint(fileName: pdf.lastPathComponent)
        if let identifier = pdfs.identifier(in: pdf), let metadata = try? await bibliography.metadata(for: identifier),
            !PaperTitle.contradicts(metadata, hint: hint)
        {
            return metadata
        }
        for title in pdfs.titleCandidates(in: pdf) {
            let results = (try? await bibliography.search(title)) ?? []
            if let found = results.first(where: {
                PaperTitle.matches($0, title: title) && !PaperTitle.contradicts($0, hint: hint)
            }) {
                return found
            }
        }
        guard hint.words.count >= 2 else { return nil }
        let results = (try? await bibliography.search(hint.query)) ?? []
        return results.first { PaperTitle.matches($0, hint: hint) }
    }

    /// 書誌情報が見つからないときの書誌情報。題名は PDF のいちばん大きい文字を使い、それが短い切れ端なら
    /// ファイル名の題名の部分を使う。著者と年は「著者_年_題名」の形のファイル名から埋める。
    private func fallbackMetadata(of pdf: URL) -> ReferenceMetadata {
        let hint = FileNameHint(fileName: pdf.lastPathComponent)
        let candidate = pdfs.titleCandidates(in: pdf).first { PaperTitle.normalize($0).count >= 20 }
        return ReferenceMetadata(
            type: .document,
            title: candidate ?? hint.title ?? pdf.deletingPathExtension().lastPathComponent,
            authors: hint.authors,
            issued: hint.year.map { PartialDate(year: $0) })
    }

    public func delete(_ ids: [UUID]) async throws(LibraryError) {
        for id in ids { try attachments.removeAttachments(of: id) }
        try await repository.deleteReferences(ids)
    }

    private func create(
        _ metadata: ReferenceMetadata, into collectionID: UUID?, existing: [Reference]
    ) async throws(LibraryError) -> Reference {
        let reference = Reference(
            metadata: metadata,
            citationKey: CitationKey.make(for: metadata, existing: Set(existing.map(\.citationKey))),
            collectionIDs: collectionID.map { [$0] } ?? [])
        try await repository.save(reference)
        return reference
    }

    // MARK: - コレクション

    public func createCollection(
        named name: String, parentID: UUID?
    ) async throws(LibraryError) -> ReferenceCollection {
        let collection = ReferenceCollection(name: name, parentID: parentID)
        try await repository.save(collection)
        return collection
    }

    public func save(_ collection: ReferenceCollection) async throws(LibraryError) {
        try await repository.save(collection)
    }

    public func moveCollection(_ id: UUID, into parentID: UUID?) async throws(LibraryError) {
        let collections = try await repository.collections()
        guard var collection = collections.first(where: { $0.id == id }) else { return }
        if let parentID, collections.descendantIDs(of: id).contains(parentID) { return }
        collection.parentID = parentID
        try await repository.save(collection)
    }

    public func deleteCollection(_ id: UUID) async throws(LibraryError) {
        try await repository.deleteCollection(id)
    }

    public func add(_ ids: [UUID], to collectionID: UUID) async throws(LibraryError) {
        for id in ids {
            guard var reference = try await repository.reference(id) else { continue }
            reference.collectionIDs.insert(collectionID)
            try await save(reference)
        }
    }

    public func remove(_ ids: [UUID], from collectionID: UUID) async throws(LibraryError) {
        for id in ids {
            guard var reference = try await repository.reference(id) else { continue }
            reference.collectionIDs.remove(collectionID)
            try await save(reference)
        }
    }

    // MARK: - 注釈

    public func annotations(of referenceID: UUID) async throws(LibraryError) -> [Annotation] {
        try await repository.annotations(of: referenceID)
    }

    public func save(_ annotation: Annotation) async throws(LibraryError) {
        try await repository.save(annotation)
    }

    public func deleteAnnotation(_ id: UUID) async throws(LibraryError) {
        try await repository.deleteAnnotation(id)
    }

    // MARK: - 書き出し

    public func bibTeX(for ids: [UUID]) async throws(LibraryError) -> String {
        let wanted = Set(ids)
        return BibTeXWriter.write(try await repository.references().filter { wanted.contains($0.id) })
    }

    public func pdfURL(of reference: Reference) -> URL? {
        reference.attachment.map(attachments.url(for:))
    }

    public var storageRoot: URL {
        attachments.root
    }
}
