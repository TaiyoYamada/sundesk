//
//  NavigatorViewModelTests.swift
//  NotesFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import NotesFeature
import Testing

@Suite("ナビゲータ")
struct NavigatorViewModelTests {
    @Test("木を読み、名前で絞り込める。ファイルかどうかと場所が分かる")
    func loadsTree() async {
        let navigator = FileNavigatorViewModel(
            syncVault: SyncVaultStub(), observeChanges: ObserveChangesStub(), locateFile: LocateFileStub())

        await navigator.reload()

        #expect(navigator.items.map(\.name) == ["量子計算", "ホーム.md"])
        #expect(navigator.items.first?.systemImage == "folder")
        #expect(navigator.isFile("ホーム.md"))
        #expect(!navigator.isFile("量子計算"))
        #expect(navigator.fileURL(for: "ホーム.md") == URL(filePath: "/vault/ホーム.md"))
        navigator.filterText = "ビット"
        #expect(navigator.items.first?.children?.map(\.name) == ["量子ビット.md"])
    }

    @Test("検索語を入れると結果が出る")
    func searches() async {
        let search = SearchViewModel(searchNotes: SearchStub())
        search.query = "固有値"

        await search.search(debounce: .zero)

        #expect(search.results.map(\.path) == ["固有値.md"])
        #expect(search.hasSearched)
    }

    @Test("タグを選ぶと、そのタグのノートが出る")
    func listsNotesForTag() async {
        let tags = TagsViewModel(listTags: TagsStub(), findNotes: TagsStub(), observeIndex: ObserveIndexStub())
        await tags.reload()
        #expect(tags.tags.map(\.name) == ["量子計算"])

        tags.selectedTag = "量子計算"
        await tags.loadNotes()

        #expect(tags.notes.map(\.title) == ["量子ビット"])
    }
}
