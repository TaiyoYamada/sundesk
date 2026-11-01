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
        let longTitle = "題名の候補として十分に長い日本語の題名です"
        let unknown = try await interactor(pdfs: FakePDFReader(identifier: .doi("10.9999/x"), titles: [longTitle]))
            .importPDF(URL(filePath: "/tmp/other.pdf"), into: nil)

        #expect(found.metadata.title == vqe.title)
        #expect(found.attachment != nil)
        #expect(unknown.metadata.title == "題名の候補として十分に長い日本語の題名です")
        #expect(unknown.metadata.type == .document)
    }

    @Test("DOI がなければ、PDF の題名で検索し、題名が合うものを採る")
    func importByTitleSearch() async throws {
        let title = "A variational eigenvalue solver on a photonic quantum processor"
        let other = ReferenceMetadata(title: "Something else entirely different")
        let library = interactor(
            bibliography: FakeBibliography(results: [title: [other, vqe]]), pdfs: FakePDFReader(titles: [title]))

        let added = try await library.importPDF(URL(filePath: "/tmp/paper.pdf"), into: nil)

        #expect(added.metadata.doi == "10.1038/ncomms5213")
    }

    @Test("題名で見つからなければ、ファイル名の語（著者、年、題名の略）で検索する")
    func importByFileName() async throws {
        let hint = FileNameHint(fileName: "2014_Peruzzo_variational-eigenvalue-solver_NatCommun.pdf")
        let library = interactor(
            bibliography: FakeBibliography(results: [hint.query: [vqe]]),
            pdfs: FakePDFReader(titles: ["( %)*++ , - ./ \"# $0%1 2"]))

        let added = try await library.importPDF(
            URL(filePath: "/tmp/2014_Peruzzo_variational-eigenvalue-solver_NatCommun.pdf"), into: nil)

        #expect(added.metadata.doi == "10.1038/ncomms5213")
    }

    @Test("見つかっていない書誌情報を探し直す。DOI のある文献は探さない")
    func findMissing() async throws {
        let title = "A variational eigenvalue solver on a photonic quantum processor"
        let library = interactor(
            bibliography: FakeBibliography(results: [title: [vqe]]), pdfs: FakePDFReader(titles: [title]))
        let found = Reference(
            metadata: ReferenceMetadata(type: .document, title: "Microsoft Word - x.doc"), attachment: "a/x.pdf")
        let edited = Reference(metadata: ReferenceMetadata(type: .book, title: "手で直した題名"), attachment: "b/y.pdf")
        let identified = Reference(metadata: vqe, attachment: "c/z.pdf")
        for reference in [found, edited, identified] { await repository.save(reference) }

        let result = try await library.findMissingMetadata { _, _ in }

        #expect(result.found == 2)
        #expect(result.total == 2)
        #expect(await repository.reference(found.id)?.metadata.doi == "10.1038/ncomms5213")
        #expect(await repository.reference(identified.id)?.metadata == vqe)
    }

    @Test("コレクションは別のコレクションの中へ移せる。自分の中へは移さない")
    func moveCollection() async throws {
        let library = interactor()
        let parent = try await library.createCollection(named: "研究", parentID: nil)
        let child = try await library.createCollection(named: "最適化", parentID: nil)

        try await library.moveCollection(child.id, into: parent.id)
        #expect(await repository.collections().first { $0.id == child.id }?.parentID == parent.id)

        try await library.moveCollection(parent.id, into: child.id)
        #expect(await repository.collections().first { $0.id == parent.id }?.parentID == nil)

        try await library.moveCollection(child.id, into: nil)
        #expect(await repository.collections().first { $0.id == child.id }?.parentID == nil)
    }

    @Test("書誌情報が見つからなければ、題名は PDF の大きな文字か、短い切れ端ならファイル名から取り、著者と年はファイル名から埋める")
    func fallbackFromFileName() async throws {
        let pdf = URL(filePath: "/tmp/Tsugawa_1992_暗算習熟者の数の保持.pdf")
        let short = try await interactor(pdfs: FakePDFReader(titles: ["暗算習熟者における"])).importPDF(pdf, into: nil)
        #expect(short.metadata.title == "暗算習熟者の数の保持")
        #expect(short.metadata.authors == [Creator(family: "Tsugawa")])
        #expect(short.metadata.issued == PartialDate(year: 1992))

        let long = try await interactor(pdfs: FakePDFReader(titles: ["珠算式暗算の習熟者における数の保持と心像の役割"]))
            .importPDF(URL(filePath: "/tmp/Tsugawa_1992_x.pdf"), into: nil)
        #expect(long.metadata.title == "珠算式暗算の習熟者における数の保持と心像の役割")
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
        // 手で付けたキーは変えない
        #expect(refreshed.citationKey == "k")
    }

    @Test("自動で付けた引用キーは、引き直した書誌情報で付け直す")
    func refreshCitationKey() async throws {
        let placeholder = ReferenceMetadata(title: "jsdt", doi: "10.1038/ncomms5213")
        let library = interactor(bibliography: FakeBibliography(metadata: [.doi("10.1038/ncomms5213"): vqe]))
        let reference = Reference(metadata: placeholder)
        try await library.save(reference)
        #expect(await repository.reference(reference.id)?.citationKey == "jsdt")

        try await library.refreshMetadata(of: reference.id)

        #expect(await repository.reference(reference.id)?.citationKey == "peruzzo2014variational")
    }
}
