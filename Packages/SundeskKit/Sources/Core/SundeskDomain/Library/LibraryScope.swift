//
//  LibraryScope.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// サイドバーで選んだ、文献の一覧の範囲。
public enum LibraryScope: Hashable, Sendable {
    case all
    /// どのコレクションにも入っていない文献。
    case unfiled
    /// そのコレクションと、中のコレクションに入っている文献。
    case collection(UUID)
    case tag(String)
}

extension [Reference] {
    /// 範囲と検索の語で絞る。語は空白で区切り、すべてを題名、著者、年、雑誌名、タグ、引用キーのどこかに含むものを残す。
    public func filtered(
        by scope: LibraryScope, query: String, collections: [ReferenceCollection]
    ) -> [Reference] {
        let inScope: [Reference] =
            switch scope {
            case .all:
                self
            case .unfiled:
                filter { $0.collectionIDs.isEmpty }
            case .collection(let id):
                filter { !$0.collectionIDs.isDisjoint(with: collections.descendantIDs(of: id)) }
            case .tag(let tag):
                filter { $0.tags.contains(tag) }
            }
        let words = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !words.isEmpty else { return inScope }
        return inScope.filter { reference in
            let haystack = reference.searchText
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// すべての文献に付いているタグ（名前順、重なりなし）。
    public var allTags: [String] {
        Set(flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

extension Reference {
    fileprivate var searchText: String {
        let metadata = metadata
        let year = metadata.issued.map { String($0.year) } ?? ""
        let fields = [metadata.title, metadata.containerTitle, citationKey, year]
        return (fields + metadata.authors.flatMap { [$0.family, $0.given] } + tags)
            .joined(separator: "\n").lowercased()
    }
}
