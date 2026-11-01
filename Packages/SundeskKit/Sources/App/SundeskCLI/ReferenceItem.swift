//
//  ReferenceItem.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// CLI と MCP サーバーが返す、1 件の文献。JSON の形は、CLI の --json と MCP のツールの結果で同じにする。
struct ReferenceItem: Codable {
    let key: String
    let type: String
    let title: String
    let authors: [String]
    let year: Int?
    let container: String
    let doi: String
    let arxiv: String
    let isbn: String
    let url: String
    let tags: [String]
    /// 入っているコレクション（「親/子」の形）。
    let collections: [String]
    /// unread、reading、read。
    let status: String
    /// 添付した PDF のパス。
    let pdf: String?
    // 次の 3 つは、1 件を詳しく見るときだけ入れる
    let abstract: String?
    let note: String?
    let summary: PaperSummary?

    init(_ reference: Reference, collections: [ReferenceCollection], pdf: URL?, detailed: Bool) {
        let metadata = reference.metadata
        key = reference.citationKey
        type = metadata.type.rawValue
        title = metadata.title
        authors = metadata.authors.map(\.displayName)
        year = metadata.issued?.year
        container = metadata.containerTitle
        doi = metadata.doi
        arxiv = metadata.arxiv
        isbn = metadata.isbn
        url = metadata.url
        tags = reference.tags
        self.collections = reference.collectionIDs.map { collections.path(of: $0) }.sorted()
        status = reference.readingStatus.rawValue
        self.pdf = pdf?.path
        abstract = detailed ? metadata.abstract : nil
        note = detailed ? reference.note : nil
        summary = detailed ? reference.summary : nil
    }

    /// 一覧の 1 行（引用キー、年、著者、題名をタブで区切る）。
    var line: String {
        let authors =
            switch authors.count {
            case 0: ""
            case 1: authors[0]
            default: "\(authors[0]) ほか"
            }
        return [key, year.map(String.init) ?? "", authors, title].joined(separator: "\t")
    }
}
