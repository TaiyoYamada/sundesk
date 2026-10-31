//
//  LibraryInteractorTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import Testing

@testable import SundeskDomain

@Suite("ライブラリの操作")
struct LibraryInteractorTests {
    private let repository = InMemoryReferenceRepository()
    private let attachments = FakeAttachmentStore()
    private let vqe = ReferenceMetadata(
        type: .journalArticle, title: "A variational eigenvalue solver on a photonic quantum processor",
        authors: [Creator(family: "Peruzzo", given: "Alberto")], issued: PartialDate(year: 2014),
        doi: "10.1038/ncomms5213")

    private func interactor(
        bibliography: FakeBibliography = FakeBibliography(), pdfs: FakePDFReader = FakePDFReader()
    ) -> LibraryInteractor {
        LibraryInteractor(repository: repository, attachments: attachments, bibliography: bibliography, pdfs: pdfs)
    }

    @Test("識別子から足すと、引用キーを付けてコレクションに入れる。同じ DOI はもう一度足さない")
    func addByIdentifier() async throws {
        let collection = UUID()
        let library = interactor(bibliography: FakeBibliography(metadata: [.doi("10.1038/ncomms5213"): vqe]))

        let added = try await library.add(.doi("10.1038/ncomms5213"), into: collection)
        let again = try await library.add(.doi("10.1038/NCOMMS5213"), into: nil)

        #expect(added.citationKey == "peruzzo2014variational")
        #expect(added.collectionIDs == [collection])
        #expect(again.id == added.id)
        #expect(await repository.references().count == 1)
    }

    @Test("arXiv から足すと、PDF も添付する")
    func addArxiv() async throws {
        let preprint = ReferenceMetadata(type: .preprint, title: "T", arxiv: "1304.3061")
        let library = interactor(bibliography: FakeBibliography(metadata: [.arxiv("1304.3061"): preprint]))

        let added = try await library.add(.arxiv("1304.3061"), into: nil)

        #expect(added.attachment == "\(added.id.uuidString)/1304.3061.pdf")
        #expect(attachments.imported[added.id] == URL(filePath: "/tmp/1304.3061.pdf"))
    }

    @Test("PDF の DOI から書誌情報を引いて足す。引けなければ PDF の題名で足す")
    func importPDF() async throws {
        let pdf = URL(filePath: "/tmp/paper.pdf")
        let found = try await interactor(
            bibliography: FakeBibliography(metadata: [.doi("10.1038/ncomms5213"): vqe]),
            pdfs: FakePDFReader(identifier: .doi("10.1038/ncomms5213"))
        ).importPDF(pdf, into: nil)
        let unknown = try await interactor(pdfs: FakePDFReader(identifier: .doi("10.9999/x"), title: "題名"))
            .importPDF(URL(filePath: "/tmp/other.pdf"), into: nil)

        #expect(found.metadata.title == vqe.title)
        #expect(found.attachment != nil)
        #expect(unknown.metadata.title == "題名")
        #expect(unknown.metadata.type == .document)
    }

    @Test("文字を読めない PDF は足さない")
    func unreadablePDF() async {
        await #expect(throws: LibraryError.unreadablePDF) {
            try await interactor(pdfs: FakePDFReader(pages: [])).importPDF(URL(filePath: "/tmp/x.pdf"), into: nil)
        }
    }

    @Test("保存すると更新日時を進め、空の引用キーを埋める")
    func save() async throws {
        let library = interactor()
        var reference = Reference(metadata: vqe, dateModified: .distantPast)
        try await library.save(reference)
        reference = try #require(await repository.reference(reference.id))

        #expect(reference.dateModified > .distantPast)
        #expect(reference.citationKey == "peruzzo2014variational")
    }

    @Test("コレクションに入れて外す。消すと添付も消す")
    func collectionsAndDelete() async throws {
        let library = interactor()
        let reference = Reference(metadata: vqe)
        try await library.save(reference)
        let collection = try await library.createCollection(named: "研究", parentID: nil)

        try await library.add([reference.id], to: collection.id)
        #expect(await repository.reference(reference.id)?.collectionIDs == [collection.id])
        try await library.remove([reference.id], from: collection.id)
        #expect(await repository.reference(reference.id)?.collectionIDs == [])

        try await library.delete([reference.id])
        #expect(await repository.references().isEmpty)
        #expect(attachments.removed == [reference.id])
    }

    @Test("書誌情報を引き直しても、タグやメモは残す")
    func refresh() async throws {
        let newer = ReferenceMetadata(title: "新しい題名", doi: "10.1038/ncomms5213")
        let library = interactor(bibliography: FakeBibliography(metadata: [.doi("10.1038/ncomms5213"): newer]))
        let reference = Reference(metadata: vqe, citationKey: "k", tags: ["VQE"], note: "メモ")
        try await library.save(reference)

        try await library.refreshMetadata(of: reference.id)

        let refreshed = try #require(await repository.reference(reference.id))
        #expect(refreshed.metadata.title == "新しい題名")
        #expect(refreshed.tags == ["VQE"])
        #expect(refreshed.note == "メモ")
    }
}
