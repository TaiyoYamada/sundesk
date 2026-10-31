//
//  BibTeXWriter.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 文献を BibTeX の項目に書き出す。
public enum BibTeXWriter {
    public static func write(_ references: [Reference]) -> String {
        references.map(entry).joined(separator: "\n\n") + (references.isEmpty ? "" : "\n")
    }

    static func entry(_ reference: Reference) -> String {
        let metadata = reference.metadata
        var fields: [(String, String)] = [
            ("author", metadata.authors.map(name).joined(separator: " and ")),
            ("title", metadata.title),
        ]
        switch metadata.type {
        case .journalArticle:
            fields.append(("journal", metadata.containerTitle))
        case .conferencePaper, .bookChapter:
            fields.append(("booktitle", metadata.containerTitle))
            fields.append(("publisher", metadata.publisher))
        case .book:
            fields.append(("publisher", metadata.publisher))
        case .thesis:
            fields.append(("school", metadata.publisher))
        case .report:
            fields.append(("institution", metadata.publisher))
        case .preprint, .webpage, .document:
            fields.append(("howpublished", metadata.containerTitle))
        }
        fields += [
            ("year", metadata.issued.map { String($0.year) } ?? ""),
            ("month", metadata.issued?.month.map(String.init) ?? ""),
            ("volume", metadata.volume),
            ("number", metadata.issue),
            ("pages", metadata.pages.replacing(/(\d)\s*[-–—]+\s*(\d)/) { "\($0.output.1)--\($0.output.2)" }),
            ("isbn", metadata.isbn),
            ("doi", metadata.doi),
            ("eprint", metadata.arxiv),
            ("archiveprefix", metadata.arxiv.isEmpty ? "" : "arXiv"),
            ("url", metadata.url),
        ]

        let body = fields.filter { !$0.1.isEmpty }
            .map { key, value in
                // DOI と URL は \url と同じく、そのまま書く（_ や % を逃がすと、リンクが壊れる）
                let text = key == "doi" || key == "url" ? value : escape(value)
                return "  \(key) = {\(text)}"
            }
            .joined(separator: ",\n")
        return "@\(entryType(metadata.type)){\(reference.citationKey),\n\(body)\n}"
    }

    private static func entryType(_ type: ReferenceType) -> String {
        switch type {
        case .journalArticle: "article"
        case .conferencePaper: "inproceedings"
        case .book: "book"
        case .bookChapter: "incollection"
        case .thesis: "phdthesis"
        case .report: "techreport"
        case .preprint, .webpage, .document: "misc"
        }
    }

    private static func name(_ creator: Creator) -> String {
        guard !creator.given.isEmpty else { return "{\(creator.family)}" }
        return "\(creator.family), \(creator.given)"
    }

    /// LaTeX で特別な意味を持つ文字を逃がす。{ } は、大文字を守るために書かれることがあるので、そのまま残す。
    private static func escape(_ text: String) -> String {
        text.replacing(/(\\?)([&%$#_])/) { "\\" + $0.output.2 }
    }
}
