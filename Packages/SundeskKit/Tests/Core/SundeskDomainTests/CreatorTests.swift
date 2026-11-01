//
//  CreatorTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Testing

@testable import SundeskDomain

@Suite("著者の名前")
struct CreatorTests {
    @Test(
        "1 つの文字列を姓と名に分ける",
        arguments: [
            ("Alberto Peruzzo", "Peruzzo", "Alberto"),
            ("Peruzzo, Alberto", "Peruzzo", "Alberto"),
            ("Peter J. Love", "Love", "Peter J."),
            ("山田 大陽", "山田", "大陽"),
            ("IBM", "IBM", ""),
        ])
    func parsing(name: String, family: String, given: String) {
        #expect(Creator(parsing: name) == Creator(family: family, given: given))
    }

    @Test("日本語の名前は姓を先に出す")
    func displayName() {
        #expect(Creator(family: "Peruzzo", given: "Alberto").displayName == "Alberto Peruzzo")
        #expect(Creator(family: "山田", given: "大陽").displayName == "山田 大陽")
    }

    @Test("一覧の著者は 3 人目から「ほか」にする")
    func authorSummary() {
        let authors = [Creator(family: "Peruzzo"), Creator(family: "McClean"), Creator(family: "Shadbolt")]
        #expect(ReferenceMetadata(authors: Array(authors.prefix(1))).authorSummary == "Peruzzo")
        #expect(ReferenceMetadata(authors: Array(authors.prefix(2))).authorSummary == "Peruzzo、McClean")
        #expect(ReferenceMetadata(authors: authors).authorSummary == "Peruzzo ほか")
    }
}
