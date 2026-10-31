//
//  SummaryDisplay.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 要約の表示。
public struct SummaryDisplay: Equatable, Sendable {
    public struct Section: Identifiable, Equatable, Sendable {
        public let title: String
        public let body: String
        public var id: String { title }
    }

    public let sections: [Section]
    public let createdAt: String

    init(_ summary: PaperSummary) {
        sections = [
            Section(title: "目的", body: summary.purpose),
            Section(title: "手法", body: summary.method),
            Section(title: "結果", body: summary.results),
            Section(title: "限界と課題", body: summary.limitations),
        ]
        createdAt = summary.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// メモに貼るための Markdown。
    public var markdown: String {
        sections.map { "## \($0.title)\n\n\($0.body)" }.joined(separator: "\n\n")
    }
}

/// 要約を作っているかどうか。
public enum SummaryState: Equatable, Sendable {
    case idle
    case running(String)
    case failed(String)
}
