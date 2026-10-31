//
//  BibliographyParsingTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain
import Testing

@testable import SundeskData

@Suite("書誌情報の応答を読む")
struct BibliographyParsingTests {
    @Test("doi.org の CSL JSON（Crossref の種類の名前、数と文字列の揺れ、HTML の文字参照）")
    func crossrefCSL() throws {
        let json = """
            {"type":"proceedings-article","title":"Optuna: A Next-generation <i>Hyperparameter</i> Framework",
             "author":[{"given":"Takuya","family":"Akiba"},{"literal":"Optuna Team"}],
             "issued":{"date-parts":[[2019,7,25]]},
             "container-title":["Proceedings of KDD &amp; Data Mining"],
             "volume":5,"page":"2623-2631","publisher":"ACM","DOI":"10.1145/3292500.3330701",
             "URL":"http://dx.doi.org/10.1145/3292500.3330701","abstract":"<jats:p>Text  here</jats:p>"}
            """
        let metadata = try #require(CSLItem.parse(Data(json.utf8)))

        #expect(metadata.type == .conferencePaper)
        #expect(metadata.title == "Optuna: A Next-generation Hyperparameter Framework")
        #expect(metadata.authors == [Creator(family: "Akiba", given: "Takuya"), Creator(family: "Optuna Team")])
        #expect(metadata.issued == PartialDate(year: 2019, month: 7, day: 25))
        #expect(metadata.containerTitle == "Proceedings of KDD & Data Mining")
        #expect(metadata.volume == "5")
        #expect(metadata.pages == "2623-2631")
        #expect(metadata.abstract == "Text here")
    }

    @Test("題名のない応答は読まない")
    func missingTitle() {
        #expect(CSLItem.parse(Data(#"{"type":"article"}"#.utf8)) == nil)
        #expect(CSLItem.parse(Data("not json".utf8)) == nil)
    }

    @Test("arXiv の Atom")
    func arxiv() throws {
        let xml = """
            <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
              <title>ArXiv Query</title>
              <entry>
                <published>2013-04-10T19:59:49Z</published>
                <title>A variational eigenvalue solver
                  on a quantum processor</title>
                <summary>  Quantum computers promise. </summary>
                <author><name>Alberto Peruzzo</name></author>
                <author><name>Jarrod McClean</name></author>
                <arxiv:doi>10.1038/ncomms5213</arxiv:doi>
              </entry>
            </feed>
            """
        let metadata = try #require(ArxivFeed.parse(Data(xml.utf8), id: "1304.3061"))

        #expect(metadata.type == .preprint)
        #expect(metadata.title == "A variational eigenvalue solver on a quantum processor")
        #expect(metadata.authors.map(\.family) == ["Peruzzo", "McClean"])
        #expect(metadata.issued == PartialDate(year: 2013, month: 4, day: 10))
        #expect(metadata.doi == "10.1038/ncomms5213")
        #expect(metadata.arxiv == "1304.3061")
        #expect(metadata.abstract == "Quantum computers promise.")
    }

    @Test("arXiv が見つからない ID に返す「Error」の項目は読まない")
    func arxivError() {
        let xml = #"<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Error</title></entry></feed>"#
        #expect(ArxivFeed.parse(Data(xml.utf8), id: "9999.99999") == nil)
    }

    @Test("Open Library の本")
    func openLibrary() throws {
        let json = """
            {"ISBN:9780262035613": {"title": "Deep Learning", "subtitle": "Adaptive Computation",
             "authors": [{"name": "Ian Goodfellow"}, {"name": "Yoshua Bengio"}],
             "publishers": [{"name": "MIT Press"}], "publish_date": "3 January 2017",
             "url": "http://openlibrary.org/books/OL26455783M/Deep_Learning"}}
            """
        let metadata = try #require(OpenLibraryBook.parse(Data(json.utf8), isbn: "9780262035613"))

        #expect(metadata.type == .book)
        #expect(metadata.title == "Deep Learning: Adaptive Computation")
        #expect(metadata.authors.map(\.family) == ["Goodfellow", "Bengio"])
        #expect(metadata.authors.map(\.given) == ["Ian", "Yoshua"])
        #expect(metadata.issued == PartialDate(year: 2017))
        #expect(metadata.publisher == "MIT Press")
        #expect(OpenLibraryBook.parse(Data("{}".utf8), isbn: "9780262035613") == nil)
    }
}
