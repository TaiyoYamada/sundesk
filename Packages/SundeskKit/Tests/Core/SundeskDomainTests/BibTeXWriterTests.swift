//
//  BibTeXWriterTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import Testing

@testable import SundeskDomain

@Suite("BibTeX の書き出し")
struct BibTeXWriterTests {
    @Test("雑誌論文")
    func article() {
        let reference = Reference(
            metadata: ReferenceMetadata(
                type: .journalArticle, title: "A variational eigenvalue solver on a photonic quantum processor",
                authors: [Creator(family: "Peruzzo", given: "Alberto"), Creator(family: "McClean", given: "Jarrod")],
                issued: PartialDate(year: 2014, month: 7, day: 23), containerTitle: "Nature Communications",
                volume: "5", issue: "1", pages: "4213", doi: "10.1038/ncomms5213"),
            citationKey: "peruzzo2014variational")

        #expect(
            BibTeXWriter.write([reference]) == """
                @article{peruzzo2014variational,
                  author = {Peruzzo, Alberto and McClean, Jarrod},
                  title = {A variational eigenvalue solver on a photonic quantum processor},
                  journal = {Nature Communications},
                  year = {2014},
                  month = {7},
                  volume = {5},
                  number = {1},
                  pages = {4213},
                  doi = {10.1038/ncomms5213}
                }

                """)
    }

    @Test("プレプリントは eprint に arXiv の ID を書く")
    func preprint() {
        let reference = Reference(
            metadata: ReferenceMetadata(type: .preprint, title: "T", arxiv: "1304.3061"), citationKey: "k")
        let entry = BibTeXWriter.entry(reference)
        #expect(entry.hasPrefix("@misc{k,"))
        #expect(entry.contains("eprint = {1304.3061}"))
        #expect(entry.contains("archiveprefix = {arXiv}"))
    }

    @Test("会議論文は booktitle、ページの範囲は --")
    func conference() {
        let reference = Reference(
            metadata: ReferenceMetadata(
                type: .conferencePaper, title: "T", containerTitle: "KDD '19", pages: "2623-2631"),
            citationKey: "k")
        let entry = BibTeXWriter.entry(reference)
        #expect(entry.hasPrefix("@inproceedings{k,"))
        #expect(entry.contains("booktitle = {KDD '19}"))
        #expect(entry.contains("pages = {2623--2631}"))
    }

    @Test("LaTeX の特別な文字を逃がす。DOI と URL と、逃がしてある文字はそのまま")
    func escaping() {
        let reference = Reference(
            metadata: ReferenceMetadata(
                title: "Q&A on 50% of #cases with x_1 and \\& done", doi: "10.1000/a_b",
                url: "https://example.com/a_b?c=1%20"),
            citationKey: "k")
        let entry = BibTeXWriter.entry(reference)
        #expect(entry.contains("title = {Q\\&A on 50\\% of \\#cases with x\\_1 and \\& done}"))
        #expect(entry.contains("doi = {10.1000/a_b}"))
        #expect(entry.contains("url = {https://example.com/a_b?c=1%20}"))
    }

    @Test("名のない著者（団体）は波かっこで包む")
    func organization() {
        let reference = Reference(
            metadata: ReferenceMetadata(title: "T", authors: [Creator(family: "IBM Quantum")]), citationKey: "k")
        #expect(BibTeXWriter.entry(reference).contains("author = {{IBM Quantum}}"))
    }
}
