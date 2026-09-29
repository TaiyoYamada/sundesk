//
//  TagsViewModel.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// ナビゲータの「タグ」。タグの一覧と、選んだタグのノート。
@MainActor
@Observable
public final class TagsViewModel {
    public private(set) var tags: [TagCount] = []
    public private(set) var notes: [NoteSummary] = []
    public var selectedTag: String?

    @ObservationIgnored private let listTags: any ListTagsUseCase
    @ObservationIgnored private let findNotes: any FindNotesByTagUseCase
    @ObservationIgnored private let observeIndex: any ObserveNoteIndexUseCase

    public init(
        listTags: any ListTagsUseCase,
        findNotes: any FindNotesByTagUseCase,
        observeIndex: any ObserveNoteIndexUseCase
    ) {
        self.listTags = listTags
        self.findNotes = findNotes
        self.observeIndex = observeIndex
    }

    /// 一覧を読み、索引が更新されるたびに読み直す。
    public func observe() async {
        await reload()
        for await _ in observeIndex() {
            await reload()
        }
    }

    public func reload() async {
        tags = (try? await listTags()) ?? []
        await loadNotes()
    }

    public func loadNotes() async {
        guard let selectedTag else {
            notes = []
            return
        }
        notes = (try? await findNotes(selectedTag)) ?? []
    }
}
