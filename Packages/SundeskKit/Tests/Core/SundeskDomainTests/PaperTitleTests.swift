//
//  PaperTitleTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Testing

@testable import SundeskDomain

@Suite("題名の候補と突き合わせ")
struct PaperTitleTests {
    @Test(
        "PDF に埋め込まれた題名のうち、題名でないものを除く",
        arguments: [
            "Microsoft Word - tr062.doc", "D:/SVN2/GECCO2013_BBOB/templateBBOBmany.dvi", "gec457-comellas.dvi",
            "( %)*++ , - ./ \"# $0%1 2", "Vol. 47 No. SIG 14(TOM 15) 情報処理学会論文誌：数理モデル化と応用 Oct. 2006",
            "IEEE TRANSACTIONS ON EVOLUTIONARY COMPUTATION, VOL. 13, NO. 2, APRIL 2009 243", "Untitled.PDF",
            "cma-es.key", "短い",
        ])
    func implausible(title: String) {
        #expect(!PaperTitle.isPlausible(title))
    }

    @Test(
        "題名らしいものは残す",
        arguments: [
            "Completely Derandomized Self-Adaptation in Evolution Strategies",
            "算盤学習支援システムのための深度カメラを用いた珠操作の認識",
            "Abacus in the Brain: A Longitudinal Functional MRI Study",
        ])
    func plausible(title: String) {
        #expect(PaperTitle.isPlausible(title))
    }

    @Test("検索の結果の題名と、副題の有無や大文字小文字が違っても合う。違う論文は合わない")
    func matchesTitle() {
        let found = ReferenceMetadata(title: "Differential Evolution and Non-separability: Using Selective Pressure")
        #expect(PaperTitle.matches(found, title: "Differential Evolution and Non-separability:"))
        let upper = "DIFFERENTIAL EVOLUTION AND NON-SEPARABILITY: USING SELECTIVE PRESSURE"
        #expect(PaperTitle.matches(found, title: upper))
        #expect(!PaperTitle.matches(found, title: "Differential evolution for large scale problems"))
    }

    @Test("短い題名と、題名の途中だけが合うものは採らない")
    func rejectsLooseTitles() {
        #expect(!PaperTitle.matches(ReferenceMetadata(title: "Preliminary"), title: "Preliminary"))
        let thesis = ReferenceMetadata(
            title: "Improving deep knowledge tracing with prediction-consistent regularization")
        #expect(!PaperTitle.matches(thesis, title: "Deep Knowledge Tracing"))
        #expect(
            !PaperTitle.matches(
                ReferenceMetadata(title: "Differential Evolution"),
                title: "Differential Evolution and Non-separability:"))
        let paper = ReferenceMetadata(title: "An idea based on honey bee swarm for numerical optimization")
        let block = "AN IDEA BASED ON HONEY BEE SWARM FOR NUMERICAL OPTIMIZATION Dervis KARABOGA"
        #expect(PaperTitle.matches(paper, title: block))
    }

    @Test("ファイル名の年と筆頭著者に食い違う書誌情報を見分ける（PDF の中の DOI が参考文献のものだったとき）")
    func contradicts() {
        let hint = FileNameHint(fileName: "Boaler_2014_timed_tests_math_anxiety.pdf")
        let cited = ReferenceMetadata(
            title: "Female teachers' math anxiety affects girls' math achievement",
            authors: [Creator(family: "Beilock")], issued: PartialDate(year: 2010))
        #expect(PaperTitle.contradicts(cited, hint: hint))
        let own = ReferenceMetadata(
            title: "Research suggests that timed tests cause math anxiety", authors: [Creator(family: "Boaler")],
            issued: PartialDate(year: 2014))
        #expect(!PaperTitle.contradicts(own, hint: hint))
        #expect(!PaperTitle.contradicts(cited, hint: FileNameHint(fileName: "Adaptive Operator Selection.pdf")))
    }

    @Test("著者のデータが壊れていても題名の語が合えば、筆頭が団体でも共著者が合えば、食い違うとしない")
    func toleratesBrokenAuthors() {
        let broken = ReferenceMetadata(
            title: "A hand full of numbers: a role for offloading in arithmetics learning?",
            authors: [Creator(family: "Annelise", given: "Annelise Júlio")], issued: PartialDate(year: 2011))
        #expect(
            !PaperTitle.contradicts(
                broken, hint: FileNameHint(fileName: "Costa_2011_fingers_offloading_arithmetic.pdf")))
        let organization = ReferenceMetadata(
            title: "Evaluating the impact of a mobile app", issued: PartialDate(year: 2025))
        var withCoauthor = organization
        withCoauthor.authors = [
            Creator(family: "University of Latvia"), Creator(family: "Juska-Mirbaha", given: "Elīna"),
        ]
        let hint = FileNameHint(fileName: "Juska_2025_mental_arithmetic_app_Latvia.pdf")
        #expect(!PaperTitle.contradicts(withCoauthor, hint: hint))
        #expect(PaperTitle.contradicts(organization, hint: hint), "著者のない結果は食い違うとみなす")
    }

    @Test("ファイル名の手がかりは、年、筆頭著者、題名の語の 2 つ以上が合えば採る")
    func matchesHint() {
        let hint = FileNameHint(fileName: "2000_Hansen_invariance-self-adaptation-correlated-mutations_PPSN.pdf")
        let paper = ReferenceMetadata(
            title: "Invariance, Self-Adaptation and Correlated Mutations in Evolution Strategies",
            authors: [Creator(family: "Hansen", given: "Nikolaus")], issued: PartialDate(year: 2000))
        #expect(PaperTitle.matches(paper, hint: hint))

        var otherYear = paper
        otherYear.issued = PartialDate(year: 2010)
        #expect(!PaperTitle.matches(otherYear, hint: hint))
        var anonymous = paper
        anonymous.authors = []
        #expect(!PaperTitle.matches(anonymous, hint: hint))
        var otherAuthor = paper
        otherAuthor.authors = [Creator(family: "Auger")]
        #expect(!PaperTitle.matches(otherAuthor, hint: hint))
    }

    @Test("ファイル名から年と語を取り出す")
    func fileNameHint() {
        let english = FileNameHint(fileName: "Barner_2016_abacus_mental_math_RCT.pdf")
        #expect(english.year == 2016)
        #expect(english.words == ["Barner", "abacus", "mental", "math", "RCT"])
        #expect(english.query == "Barner abacus mental math RCT 2016")

        let japanese = FileNameHint(fileName: "Tsugawa_1992_暗算習熟者の数の保持.pdf")
        #expect(japanese.year == 1992)
        #expect(japanese.words == ["Tsugawa", "暗算習熟者の数の保持"])

        let plain = FileNameHint(fileName: "Adaptive Operator Selection for Meta-Heuristics - A Survey.pdf")
        #expect(plain.year == nil)
    }
}
