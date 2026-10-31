//
//  LibraryScopeTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import Testing

@testable import SundeskDomain

@Suite("一覧の絞り込み")
struct LibraryScopeTests {
    private let parent = ReferenceCollection(name: "研究")
    private let child: ReferenceCollection
    private let references: [Reference]

    init() {
        child = ReferenceCollection(name: "最適化", parentID: parent.id)
        references = [
            Reference(
                metadata: ReferenceMetadata(
                    title: "A variational eigenvalue solver", authors: [Creator(family: "Peruzzo")],
                    issued: PartialDate(year: 2014)),
                tags: ["VQE"], collectionIDs: [child.id]),
            Reference(
                metadata: ReferenceMetadata(title: "Quantum annealing", issued: PartialDate(year: 1998)),
                tags: ["アニーリング"], collectionIDs: [parent.id]),
            Reference(metadata: ReferenceMetadata(title: "Deep Learning")),
        ]
    }

    private func titles(_ scope: LibraryScope, _ query: String = "") -> [String] {
        references.filtered(by: scope, query: query, collections: [parent, child]).map(\.metadata.title)
    }

    @Test("コレクションは中のコレクションの文献も含む")
    func collection() {
        #expect(titles(.collection(parent.id)) == ["A variational eigenvalue solver", "Quantum annealing"])
        #expect(titles(.collection(child.id)) == ["A variational eigenvalue solver"])
    }

    @Test("未整理とタグ")
    func unfiledAndTag() {
        #expect(titles(.unfiled) == ["Deep Learning"])
        #expect(titles(.tag("アニーリング")) == ["Quantum annealing"])
    }

    @Test("検索の語はすべてを含むものを残す（大文字小文字は区別しない）")
    func query() {
        #expect(titles(.all, "peruzzo 2014") == ["A variational eigenvalue solver"])
        #expect(titles(.all, "QUANTUM") == ["Quantum annealing"])
        #expect(titles(.all, "vqe") == ["A variational eigenvalue solver"])
        #expect(titles(.all, "peruzzo 1998").isEmpty)
    }

    @Test("タグの一覧は重なりなく名前順")
    func allTags() {
        #expect(references.allTags == ["VQE", "アニーリング"])
    }
}
