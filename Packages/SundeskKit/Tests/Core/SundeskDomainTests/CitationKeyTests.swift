//
//  CitationKeyTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Testing

@testable import SundeskDomain

@Suite("引用キー")
struct CitationKeyTests {
    private let metadata = ReferenceMetadata(
        title: "A variational eigenvalue solver on a photonic quantum processor",
        authors: [Creator(family: "Peruzzo", given: "Alberto")], issued: PartialDate(year: 2014))

    @Test("姓、年、題名の最初の語（冠詞などは飛ばす）")
    func basic() {
        #expect(CitationKey.make(for: metadata, existing: []) == "peruzzo2014variational")
    }

    @Test("重なると末尾に a、b を付ける")
    func collision() {
        #expect(CitationKey.make(for: metadata, existing: ["peruzzo2014variational"]) == "peruzzo2014variationala")
        #expect(
            CitationKey.make(for: metadata, existing: ["peruzzo2014variational", "peruzzo2014variationala"])
                == "peruzzo2014variationalb")
    }

    @Test("アクセントを外し、英数字でない姓は使わない")
    func nonASCII() {
        let accented = ReferenceMetadata(title: "Über alles", authors: [Creator(family: "Aspuru-Guzik", given: "Alán")])
        #expect(CitationKey.make(for: accented, existing: []) == "aspuruguzikuber")
        let japanese = ReferenceMetadata(
            title: "量子アニーリング", authors: [Creator(family: "山田")], issued: PartialDate(year: 2026))
        #expect(CitationKey.make(for: japanese, existing: []) == "2026")
        #expect(CitationKey.make(for: ReferenceMetadata(), existing: []) == "ref")
    }
}
