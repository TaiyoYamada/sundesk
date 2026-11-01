//
//  Reference.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// ライブラリに入れた 1 件の文献。書誌情報と、ライブラリでの扱い（タグ、コレクション、メモ、PDF、要約）を持つ。
public struct Reference: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var metadata: ReferenceMetadata
    /// BibTeX で引くときのキー（例: peruzzo2014variational）。
    public var citationKey: String
    public var tags: [String]
    public var collectionIDs: Set<UUID>
    public var readingStatus: ReadingStatus
    /// Markdown のメモ。
    public var note: String
    /// 添付した PDF の、保存先のフォルダからのパス。
    public var attachment: String?
    public var summary: PaperSummary?
    public var dateAdded: Date
    public var dateModified: Date

    public init(
        id: UUID = UUID(), metadata: ReferenceMetadata, citationKey: String = "", tags: [String] = [],
        collectionIDs: Set<UUID> = [], readingStatus: ReadingStatus = .unread, note: String = "",
        attachment: String? = nil, summary: PaperSummary? = nil, dateAdded: Date = .now, dateModified: Date = .now
    ) {
        self.id = id
        self.metadata = metadata
        self.citationKey = citationKey
        self.tags = tags
        self.collectionIDs = collectionIDs
        self.readingStatus = readingStatus
        self.note = note
        self.attachment = attachment
        self.summary = summary
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }
}

public enum ReadingStatus: String, CaseIterable, Sendable {
    case unread
    case reading
    case read
}
