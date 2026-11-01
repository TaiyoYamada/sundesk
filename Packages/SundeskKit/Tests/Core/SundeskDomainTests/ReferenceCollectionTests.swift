//
//  ReferenceCollectionTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain
import Testing

@Suite("コレクションの名前")
struct ReferenceCollectionTests {
    private let research = ReferenceCollection(name: "研究")
    private let optimization: ReferenceCollection
    private let reading = ReferenceCollection(name: "読む")
    private let optimizationReading: ReferenceCollection
    private let collections: [ReferenceCollection]

    init() {
        optimization = ReferenceCollection(name: "最適化", parentID: research.id)
        optimizationReading = ReferenceCollection(name: "読む", parentID: optimization.id)
        collections = [research, optimization, reading, optimizationReading]
    }

    @Test("親からたどった名前を / でつなぐ")
    func path() {
        #expect(collections.path(of: research.id) == "研究")
        #expect(collections.path(of: optimizationReading.id) == "研究/最適化/読む")
    }

    @Test("名前だけなら、同じ名前のコレクションをすべて返す")
    func matchingName() {
        #expect(collections.matching("最適化") == [optimization])
        #expect(collections.matching("読む") == [reading, optimizationReading])
        #expect(collections.matching("ない").isEmpty)
    }

    @Test("「親/子」の形なら、道筋が合うものだけを返す")
    func matchingPath() {
        #expect(collections.matching("研究/最適化/読む") == [optimizationReading])
        #expect(collections.matching("最適化/読む").isEmpty)
    }
}
