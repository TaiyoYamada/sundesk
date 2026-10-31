//
//  CSLItem.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// doi.org が返す CSL JSON。Crossref の DOI では、種類が Crossref の名前になり、値の型も揺れる
/// （題名が文字列か配列か、巻が文字列か数か）ので、どちらでも読めるようにしている。
struct CSLItem: Decodable {
    struct Name: Decodable {
        let family: String?
        let given: String?
        let literal: String?
        let name: String?
    }

    let type: String?
    let title: FlexibleText?
    let author: [Name]?
    let editor: [Name]?
    let issued: CSLDate?
    let publishedPrint: CSLDate?
    let publishedOnline: CSLDate?
    let containerTitle: FlexibleText?
    let volume: FlexibleText?
    let issue: FlexibleText?
    let page: FlexibleText?
    let publisher: FlexibleText?
    let doi: FlexibleText?
    let url: FlexibleText?
    let isbn: FlexibleText?
    let abstract: FlexibleText?

    enum CodingKeys: String, CodingKey {
        case type, title, author, editor, issued, volume, issue, page, publisher, abstract
        case publishedPrint = "published-print"
        case publishedOnline = "published-online"
        case containerTitle = "container-title"
        case doi = "DOI"
        case url = "URL"
        case isbn = "ISBN"
    }

    static func parse(_ data: Data) -> ReferenceMetadata? {
        guard let item = try? JSONDecoder().decode(CSLItem.self, from: data),
            let title = item.title?.value.map(BibliographyText.clean), !title.isEmpty
        else { return nil }
        let names = item.author ?? item.editor ?? []
        return ReferenceMetadata(
            type: ReferenceType(csl: item.type ?? ""),
            title: title,
            authors: names.compactMap { name in
                if let family = name.family { return Creator(family: family, given: name.given ?? "") }
                return (name.literal ?? name.name).map { Creator(family: $0) }
            },
            issued: (item.issued ?? item.publishedPrint ?? item.publishedOnline)?.partialDate,
            containerTitle: item.containerTitle?.value.map(BibliographyText.clean) ?? "",
            volume: item.volume?.value ?? "",
            issue: item.issue?.value ?? "",
            pages: item.page?.value ?? "",
            publisher: item.publisher?.value ?? "",
            doi: item.doi?.value ?? "",
            isbn: item.isbn?.value ?? "",
            url: item.url?.value ?? "",
            abstract: item.abstract?.value.map(BibliographyText.clean) ?? "")
    }
}

/// 文字列、数、その配列のどれでも読み、最初の値を文字列にする。
struct FlexibleText: Decodable {
    let value: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else if let texts = try? container.decode([FlexibleText].self) {
            value = texts.lazy.compactMap(\.value).first
        } else {
            value = nil
        }
    }
}

/// CSL の日付（date-parts）。
struct CSLDate: Decodable {
    let dateParts: [[FlexibleText]]?

    enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }

    var partialDate: PartialDate? {
        dateParts?.first.flatMap { parts in PartialDate(parts: parts.compactMap { $0.value.flatMap { Int($0) } }) }
    }
}
