//
//  LibraryAccessTests.swift
//  SundeskCLITests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain
import Testing

@testable import SundeskCLI

@Suite("CLI のライブラリの操作")
struct LibraryAccessTests {
    private let vqe = ReferenceMetadata(
        title: "A variational eigenvalue solver", authors: [Creator(family: "Peruzzo", given: "Alberto")],
        issued: PartialDate(year: 2014), doi: "10.1038/ncomms5213")
    private let qaoa = ReferenceMetadata(
        title: "A Quantum Approximate Optimization Algorithm", authors: [Creator(family: "Farhi", given: "Edward")],
        issued: PartialDate(year: 2014), arxiv: "1411.4028")

    private func makeLibrary() async throws -> LibraryAccess {
        let access = try makeAccess(metadata: [.doi("10.1038/ncomms5213"): vqe, .arxiv("1411.4028"): qaoa])
        let research = try await access.library.createCollection(named: "研究", parentID: nil)
        _ = try await access.library.createCollection(named: "量子", parentID: research.id)
        _ = try await access.library.createCollection(named: "量子", parentID: nil)
        _ = try await access.add("10.1038/ncomms5213", collection: "研究/量子")
        _ = try await access.add("arXiv:1411.4028", collection: nil)
        #expect(try await access.library.references().count == 2)
        return access
    }

    @Test("コレクションを「親/子」で指して探すと、その中の文献だけが出る")
    func searchInCollection() async throws {
        let access = try await makeLibrary()

        let all = try await access.search("", collection: nil, tag: nil, limit: nil)
        let inResearch = try await access.search("", collection: "研究", tag: nil, limit: nil)
        let found = try await access.search("eigenvalue", collection: nil, tag: nil, limit: nil)

        #expect(all.map(\.key) == ["farhi2014quantum", "peruzzo2014variational"])
        #expect(inResearch.map(\.key) == ["peruzzo2014variational"])
        #expect(inResearch[0].collections == ["研究/量子"])
        #expect(found.map(\.key) == ["peruzzo2014variational"])
    }

    @Test("同じ名前のコレクションが 2 つあると、名前だけでは入れられない")
    func ambiguousCollection() async throws {
        let access = try await makeLibrary()

        await #expect(throws: CommandError.self) {
            try await access.collect(keys: ["farhi2014quantum"], into: "量子")
        }
        let collected = try await access.collect(keys: ["farhi2014quantum"], into: "研究/量子")

        #expect(collected.map(\.collections) == [["研究/量子"]])
    }

    @Test("同じ DOI をもう一度足しても、増えない")
    func addTwice() async throws {
        let access = try await makeLibrary()

        let again = try await access.add("https://doi.org/10.1038/ncomms5213", collection: nil)

        #expect(again.key == "peruzzo2014variational")
        #expect(try await access.library.references().count == 2)
    }

    @Test("識別子として読めないものは足さない")
    func invalidSource() async throws {
        let access = try await makeLibrary()

        await #expect(throws: LibraryError.invalidIdentifier("not an id")) {
            try await access.add("not an id", collection: nil)
        }
    }

    @Test("1 件を詳しく見ると、要旨とメモも入る")
    func detail() async throws {
        let access = try await makeLibrary()

        let item = try await access.reference(key: "peruzzo2014variational")

        #expect(item.abstract?.isEmpty == true)
        #expect(item.note?.isEmpty == true)
        #expect(try await access.search("", collection: nil, tag: nil, limit: 1).first?.note == nil)
    }
}
