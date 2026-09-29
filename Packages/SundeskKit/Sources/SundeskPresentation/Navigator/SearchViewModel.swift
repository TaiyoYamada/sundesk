//
//  SearchViewModel.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// ナビゲータの「検索」。ノートのタイトルと本文を探す。
@MainActor
@Observable
public final class SearchViewModel {
    public var query = ""
    public private(set) var results: [SearchResult] = []
    public private(set) var hasSearched = false

    @ObservationIgnored private let searchNotes: any SearchNotesUseCase

    public init(searchNotes: any SearchNotesUseCase) {
        self.searchNotes = searchNotes
    }

    /// 入力が止まってから検索する。View の `.task(id: query)` から呼ぶ。
    public func search(debounce: Duration = .milliseconds(200)) async {
        try? await Task.sleep(for: debounce)
        guard !Task.isCancelled else { return }
        let query = query
        let found = (try? await searchNotes(query)) ?? []
        guard !Task.isCancelled else { return }
        results = found
        hasSearched = !query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
