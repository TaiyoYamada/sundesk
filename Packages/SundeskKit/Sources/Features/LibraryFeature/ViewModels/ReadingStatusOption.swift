//
//  ReadingStatusOption.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 読んだ状態の選択肢。
nonisolated public enum ReadingStatusOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    case unread
    case reading
    case read

    public var id: Self { self }

    init(_ status: ReadingStatus) {
        switch status {
        case .unread: self = .unread
        case .reading: self = .reading
        case .read: self = .read
        }
    }

    var status: ReadingStatus {
        switch self {
        case .unread: .unread
        case .reading: .reading
        case .read: .read
        }
    }

    public var title: String {
        switch self {
        case .unread: "未読"
        case .reading: "読んでいる"
        case .read: "読んだ"
        }
    }

    public var systemImage: String {
        switch self {
        case .unread: "circle"
        case .reading: "circle.lefthalf.filled"
        case .read: "checkmark.circle.fill"
        }
    }
}
