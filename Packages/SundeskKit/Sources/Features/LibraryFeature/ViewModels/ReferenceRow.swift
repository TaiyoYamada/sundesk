//
//  ReferenceRow.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 文献の一覧の 1 行。
nonisolated public struct ReferenceRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let authors: String
    /// 並べ替えのための年（なければ 0）。
    public let year: Int
    public let container: String
    public let dateAdded: Date
    public let hasPDF: Bool
    public let status: ReadingStatusOption

    init(_ reference: Reference) {
        let metadata = reference.metadata
        id = reference.id
        title = metadata.title
        authors = metadata.authorSummary
        year = metadata.issued?.year ?? 0
        container = metadata.containerTitle
        dateAdded = reference.dateAdded
        hasPDF = reference.attachment != nil
        status = ReadingStatusOption(reference.readingStatus)
    }

    /// 年の列に出す文字。
    public var yearText: String {
        year == 0 ? "" : String(year)
    }
}
