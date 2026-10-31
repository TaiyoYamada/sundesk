//
//  LibraryViewModelTests.swift
//  LibraryFeatureTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain
import Testing

@testable import LibraryFeature

@MainActor
@Suite("ライブラリの画面")
struct LibraryViewModelTests {
    @Test("識別子から足すと、一覧に出て選ばれる。読めない識別子は知らせる")
    func addByIdentifier() async throws {
        let metadata = ReferenceMetadata(
            title: "A variational eigenvalue solver", authors: [Creator(family: "Peruzzo")],
            issued: PartialDate(year: 2014))
        let viewModel = try TestLibrary(metadata: [.arxiv("1304.3061"): metadata]).dependencies.makeLibrary()
        let watching = Task { await viewModel.start() }
        defer { watching.cancel() }

        #expect(await viewModel.add(identifier: "量子") == false)
        #expect(viewModel.errorMessage?.contains("読めませんでした") == true)

        #expect(await viewModel.add(identifier: "arXiv:1304.3061v2"))
        let row = try #require(viewModel.rows.first)
        #expect(row.title == "A variational eigenvalue solver")
        #expect(row.authors == "Peruzzo")
        #expect(row.yearText == "2014")
        #expect(row.hasPDF)
        #expect(viewModel.selection == [row.id])
    }

    @Test("コレクションを作ると選ばれ、そこで足した文献はそのコレクションに入る")
    func collections() async throws {
        let viewModel = try TestLibrary().dependencies.makeLibrary()
        let watching = Task { await viewModel.start() }
        defer { watching.cancel() }

        await viewModel.createCollection(named: "研究", parentID: nil)
        let collectionID = try #require(viewModel.selectedCollectionID)
        await viewModel.createCollection(named: "最適化", parentID: collectionID)
        await viewModel.addBlank()

        #expect(viewModel.rows.count == 1)
        #expect(viewModel.collectionTree.first?.name == "研究")
        #expect(viewModel.collectionTree.first?.children?.map(\.name) == ["最適化"])
        #expect(viewModel.collectionChoices.map(\.path) == ["研究", "研究 / 最適化"])
        #expect(viewModel.exportFileName == "最適化.bib")

        viewModel.sidebarSelection = .collection(collectionID)
        #expect(viewModel.rows.count == 1, "親のコレクションは中のコレクションの文献も見せる")
        viewModel.sidebarSelection = .unfiled
        #expect(viewModel.rows.isEmpty)
    }

    @Test("検索で絞り、消すと一覧と選択から外れる")
    func searchAndDelete() async throws {
        let viewModel = try TestLibrary().dependencies.makeLibrary()
        let watching = Task { await viewModel.start() }
        defer { watching.cancel() }
        await viewModel.addBlank()
        await viewModel.addBlank()
        #expect(viewModel.rows.count == 2)

        viewModel.query = "見つからない語"
        #expect(viewModel.rows.isEmpty)
        viewModel.query = "無題"
        #expect(viewModel.rows.count == 2)

        let ids = Set(viewModel.rows.map(\.id))
        viewModel.selection = ids
        await viewModel.delete(ids)
        await waitUntil { viewModel.rows.isEmpty }
        #expect(viewModel.selection.isEmpty)
    }
}
