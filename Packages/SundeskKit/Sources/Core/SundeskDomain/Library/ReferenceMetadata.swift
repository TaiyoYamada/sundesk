//
//  ReferenceMetadata.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 文献の書誌情報。項目は CSL JSON に合わせている（引用の書式を作るときに、そのまま渡せるように）。
/// 空の文字列は「値がない」を表す。
public struct ReferenceMetadata: Equatable, Sendable {
    public var type: ReferenceType
    public var title: String
    public var authors: [Creator]
    public var issued: PartialDate?
    /// 載った雑誌、会議録、本（章のとき）の名前。
    public var containerTitle: String
    public var volume: String
    public var issue: String
    public var pages: String
    /// 出版社。学位論文では大学、報告書では機関。
    public var publisher: String
    public var doi: String
    public var arxiv: String
    public var isbn: String
    public var url: String
    public var abstract: String

    public init(
        type: ReferenceType = .journalArticle, title: String = "", authors: [Creator] = [],
        issued: PartialDate? = nil, containerTitle: String = "", volume: String = "", issue: String = "",
        pages: String = "", publisher: String = "", doi: String = "", arxiv: String = "", isbn: String = "",
        url: String = "", abstract: String = ""
    ) {
        self.type = type
        self.title = title
        self.authors = authors
        self.issued = issued
        self.containerTitle = containerTitle
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.publisher = publisher
        self.doi = doi
        self.arxiv = arxiv
        self.isbn = isbn
        self.url = url
        self.abstract = abstract
    }

    /// 一覧に出す著者（「Peruzzo」「Peruzzo、McClean」「Peruzzo ほか」）。
    public var authorSummary: String {
        switch authors.count {
        case 0: ""
        case 1: authors[0].family
        case 2: "\(authors[0].family)、\(authors[1].family)"
        default: "\(authors[0].family) ほか"
        }
    }

    /// この識別子で表される文献か。
    public func matches(_ identifier: ReferenceIdentifier) -> Bool {
        switch identifier {
        case .doi(let value): !doi.isEmpty && doi.lowercased() == value.lowercased()
        case .arxiv(let value): arxiv == value
        case .isbn(let value): ReferenceIdentifier(parsing: isbn) == .isbn(value)
        }
    }
}
