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

    @Test("アクセントを外す")
    func accented() {
        let accented = ReferenceMetadata(title: "Über alles", authors: [Creator(family: "Aspuru-Guzik", given: "Alán")])
        #expect(CitationKey.make(for: accented, existing: []) == "aspuruguzikuber")
        #expect(CitationKey.make(for: ReferenceMetadata(), existing: []) == "ref")
    }

    @Test("数字だけの語は、題名の最初の語にしない")
    func numericWord() {
        let fileName = ReferenceMetadata(title: "2005_Ronkkonen_DE_CEC2005", issued: PartialDate(year: 2005))
        #expect(CitationKey.make(for: fileName, existing: []) == "2005ronkkonen")
    }

    @Test("日本語の姓と題名は、読みのローマ字にする。英字の語はそのまま")
    func japanese() {
        let gamification = ReferenceMetadata(
            title: "ゲーミフィケーションの要素を取り入れた電子教材", authors: [Creator(family: "福山")],
            issued: PartialDate(year: 2017))
        let ict = ReferenceMetadata(
            title: "ICTを活用した授業", authors: [Creator(family: "長谷川")], issued: PartialDate(year: 2015))

        #expect(CitationKey.make(for: gamification, existing: []) == "fukuyama2017gemifikeshon")
        #expect(CitationKey.make(for: ict, existing: []) == "hasegawa2015ict")
    }
}
