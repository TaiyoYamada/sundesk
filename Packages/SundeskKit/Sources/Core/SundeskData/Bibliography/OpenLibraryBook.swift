//
//  OpenLibraryBook.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// Open Library の Books API（jscmd=data）が返す JSON。
struct OpenLibraryBook: Decodable {
    struct Named: Decodable {
        let name: String
    }

    let title: String
    let subtitle: String?
    let authors: [Named]?
    let publishers: [Named]?
    let publishDate: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, authors, publishers, url
        case publishDate = "publish_date"
    }

    static func parse(_ data: Data, isbn: String) -> ReferenceMetadata? {
        guard let books = try? JSONDecoder().decode([String: OpenLibraryBook].self, from: data),
            let book = books["ISBN:\(isbn)"]
        else { return nil }
        // 出版日は「3 January 2017」「2017」などの形で来るので、4 桁の年だけを拾う
        let year = book.publishDate?.firstMatch(of: /\d{4}/).flatMap { Int($0.output) }
        return ReferenceMetadata(
            type: .book,
            title: [book.title, book.subtitle].compactMap { $0 }.joined(separator: ": "),
            authors: (book.authors ?? []).map { Creator(parsing: $0.name) },
            issued: year.map { PartialDate(year: $0) },
            publisher: book.publishers?.first?.name ?? "",
            isbn: isbn,
            url: book.url ?? "")
    }
}
