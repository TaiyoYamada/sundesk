//
//  ArxivFeed.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// arXiv の API が返す Atom の XML。
enum ArxivFeed {
    static func parse(_ data: Data, id: String) -> ReferenceMetadata? {
        let delegate = ArxivParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // 見つからない ID には、題名が「Error」の項目が返る
        guard parser.parse(), let title = delegate.title, title != "Error" else { return nil }
        return ReferenceMetadata(
            type: .preprint,
            title: BibliographyText.clean(title),
            authors: delegate.authors.map { Creator(parsing: BibliographyText.clean($0)) },
            issued: delegate.published.flatMap { PartialDate(parsing: String($0.prefix(10))) },
            doi: delegate.doi.map(BibliographyText.clean) ?? "",
            arxiv: id,
            url: "https://arxiv.org/abs/\(id)",
            abstract: delegate.summary.map(BibliographyText.clean) ?? "")
    }
}

private final class ArxivParserDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var summary: String?
    var published: String?
    var doi: String?
    var authors: [String] = []
    private var inEntry = false
    private var inAuthor = false
    private var text = ""

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if elementName == "entry" { inEntry = true }
        if elementName == "author" { inAuthor = true }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard inEntry else { return }
        switch elementName {
        case "title": title = text
        case "summary": summary = text
        case "published": published = text
        case "name" where inAuthor: authors.append(text)
        case "author": inAuthor = false
        case "arxiv:doi", "doi": doi = text
        case "entry": inEntry = false
        default: break
        }
    }
}
