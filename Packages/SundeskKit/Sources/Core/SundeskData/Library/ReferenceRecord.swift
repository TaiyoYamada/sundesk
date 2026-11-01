//
//  ReferenceRecord.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SwiftData

/// 文献 1 件（``Reference``）の保存の形。
@Model
final class ReferenceRecord {
    @Attribute(.unique) var id: UUID
    var type: String
    var title: String
    /// [Creator] の JSON。
    var authors: Data
    /// 「2014」「2014-07」「2014-07-23」。なければ空。
    var issued: String
    var containerTitle: String
    var volume: String
    var issue: String
    var pages: String
    var publisher: String
    var doi: String
    var arxiv: String
    var isbn: String
    var url: String
    var abstract: String
    var citationKey: String
    var tags: [String]
    var readingStatus: String
    var note: String
    var attachment: String?
    /// PaperSummary の JSON。
    var summary: Data?
    var dateAdded: Date
    var dateModified: Date
    @Relationship(inverse: \CollectionRecord.references) var collections: [CollectionRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \AnnotationRecord.reference) var annotations: [AnnotationRecord] =
        []

    init(id: UUID) {
        self.id = id
        type = ""
        title = ""
        authors = Data()
        issued = ""
        containerTitle = ""
        volume = ""
        issue = ""
        pages = ""
        publisher = ""
        doi = ""
        arxiv = ""
        isbn = ""
        url = ""
        abstract = ""
        citationKey = ""
        tags = []
        readingStatus = ""
        note = ""
        dateAdded = .now
        dateModified = .now
    }
}
