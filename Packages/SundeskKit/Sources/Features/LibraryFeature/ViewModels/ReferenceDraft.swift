//
//  ReferenceDraft.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 書誌情報の編集欄。画面ではすべて文字で編集し、保存するときに文献の形に戻す。
public struct ReferenceDraft: Equatable, Sendable {
    public var type: ReferenceTypeOption
    public var title: String
    /// 1 行に 1 人（「姓, 名」）。
    public var authors: String
    /// 「2014」「2014-07」「2014-07-23」。
    public var date: String
    public var containerTitle: String
    public var volume: String
    public var issue: String
    public var pages: String
    public var publisher: String
    public var doi: String
    public var arxiv: String
    public var isbn: String
    public var url: String
    public var abstract: String
    public var citationKey: String
    public var tags: [String]
    public var status: ReadingStatusOption
    public var note: String

    init(_ reference: Reference) {
        let metadata = reference.metadata
        type = ReferenceTypeOption(metadata.type)
        title = metadata.title
        authors = metadata.authors.map { $0.given.isEmpty ? $0.family : "\($0.family), \($0.given)" }
            .joined(separator: "\n")
        date = metadata.issued?.text ?? ""
        containerTitle = metadata.containerTitle
        volume = metadata.volume
        issue = metadata.issue
        pages = metadata.pages
        publisher = metadata.publisher
        doi = metadata.doi
        arxiv = metadata.arxiv
        isbn = metadata.isbn
        url = metadata.url
        abstract = metadata.abstract
        citationKey = reference.citationKey
        tags = reference.tags
        status = ReadingStatusOption(reference.readingStatus)
        note = reference.note
    }

    /// 編集した値を文献に書き戻す（ID、コレクション、PDF、要約はそのまま）。
    func apply(to reference: inout Reference) {
        reference.metadata = ReferenceMetadata(
            type: type.type,
            title: title,
            authors: authors.split(separator: "\n").map { Creator(parsing: String($0)) }
                .filter { !$0.family.isEmpty },
            issued: PartialDate(parsing: date.trimmingCharacters(in: .whitespaces)),
            containerTitle: containerTitle,
            volume: volume,
            issue: issue,
            pages: pages,
            publisher: publisher,
            doi: doi.trimmingCharacters(in: .whitespaces),
            arxiv: arxiv.trimmingCharacters(in: .whitespaces),
            isbn: isbn.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces),
            abstract: abstract)
        reference.citationKey = citationKey.trimmingCharacters(in: .whitespaces)
        reference.tags = tags
        reference.readingStatus = status.status
        reference.note = note
    }
}
