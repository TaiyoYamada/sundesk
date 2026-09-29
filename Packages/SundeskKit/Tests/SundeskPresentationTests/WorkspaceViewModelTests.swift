//
//  WorkspaceViewModelTests.swift
//  SundeskPresentationTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SundeskPresentation
import Testing

@MainActor
@Suite("WorkspaceViewModel")
struct WorkspaceViewModelTests {
    private func makeWorkspace(links: [String: String] = [:]) -> WorkspaceViewModel {
        WorkspaceViewModel(resolveLink: ResolveLinkStub(links: links)) { path in
            DocumentViewModel(path: path, openDocument: OpenDocumentStub(), findBacklinks: FindBacklinksStub())
        }
    }

    @Test("開くとタブが増えて選ばれる。同じファイルは 2 つ開かない")
    func opensAndReusesTabs() {
        let workspace = makeWorkspace()

        workspace.open(path: "a.md")
        workspace.open(path: "b.md")
        workspace.open(path: "a.md")

        #expect(workspace.tabs.map(\.documentPath) == ["a.md", "b.md"])
        #expect(workspace.selectedTab?.documentPath == "a.md")
    }

    @Test("新しいタブは、選んでいるタブのすぐ右に開く")
    func opensNextToSelectedTab() {
        let workspace = makeWorkspace()
        workspace.open(path: "a.md")
        workspace.open(path: "b.md")
        workspace.selectedTabID = workspace.tabs[0].id

        workspace.open(feature: .graph)

        #expect(workspace.tabs.map(\.title) == ["a", "知識グラフ", "b"])
    }

    @Test("選んでいるタブを閉じると、隣のタブが選ばれる")
    func closingSelectsNeighbor() {
        let workspace = makeWorkspace()
        for path in ["a.md", "b.md", "c.md"] { workspace.open(path: path) }
        workspace.selectedTabID = workspace.tabs[1].id

        workspace.closeSelectedTab()
        #expect(workspace.selectedTab?.documentPath == "c.md")

        workspace.closeSelectedTab()
        #expect(workspace.selectedTab?.documentPath == "a.md")

        workspace.closeSelectedTab()
        #expect(workspace.selectedTab == nil)
    }

    @Test("隣のタブへ移る。端からは反対の端へ", arguments: [(1, "a.md"), (-1, "b.md")])
    func selectsAdjacentTabWrappingAround(offset: Int, expected: String) {
        let workspace = makeWorkspace()
        for path in ["a.md", "b.md", "c.md"] { workspace.open(path: path) }

        workspace.selectAdjacentTab(offset: offset)

        #expect(workspace.selectedTab?.documentPath == expected)
    }

    @Test("同じファイルの ViewModel は使い回し、タブを閉じたら捨てる")
    func reusesDocumentViewModels() {
        let workspace = makeWorkspace()
        workspace.open(path: "a.md")
        let first = workspace.document(for: "a.md")

        #expect(workspace.document(for: "a.md") === first)
        workspace.closeSelectedTab()
        #expect(workspace.document(for: "a.md") !== first)
    }

    @Test("リンク先が見つかれば開き、なければメッセージを出す")
    func opensLinks() async {
        let workspace = makeWorkspace(links: ["量子ゲート": "量子計算/量子ゲート.md"])

        await workspace.openLink("量子ゲート", isExactPath: false)
        #expect(workspace.selectedTab?.documentPath == "量子計算/量子ゲート.md")

        await workspace.openLink("ない", isExactPath: false)
        #expect(workspace.alertMessage == "リンク先「ない」が見つかりません。")
    }

    @Test("タブの名前は、Markdown なら拡張子を出さない")
    func tabTitles() {
        #expect(WorkspaceTab(content: .document("論文メモ/Attention.md")).title == "Attention")
        #expect(WorkspaceTab(content: .document("資料/図.png")).title == "図.png")
        #expect(WorkspaceTab(content: .feature(.chat)).title == "チャット")
    }
}

@MainActor
@Suite("DocumentViewModel")
struct DocumentViewModelTests {
    @Test("Markdown は表示から始まり、ソースに切り替えられる")
    func markdownTogglesBetweenModes() {
        let document = DocumentViewModel(
            path: "a.md", openDocument: OpenDocumentStub(), findBacklinks: FindBacklinksStub())

        #expect(document.displayMode == .rendered)
        #expect(document.canToggleDisplayMode)
        document.toggleDisplayMode()
        #expect(document.displayMode == .source)
    }

    @Test("コードはソースだけ、画像は表示だけで、切り替えられない")
    func codeAndImagesDoNotToggle() {
        let code = DocumentViewModel(
            path: "a.swift", openDocument: OpenDocumentStub(), findBacklinks: FindBacklinksStub())
        let image = DocumentViewModel(
            path: "a.png", openDocument: OpenDocumentStub(), findBacklinks: FindBacklinksStub())

        #expect(code.displayMode == .source)
        code.toggleDisplayMode()
        #expect(code.displayMode == .source)
        #expect(image.displayMode == .rendered)
        #expect(!image.canToggleDisplayMode)
    }

    @Test("読み込むと、タイトル、プロパティ、タグ、バックリンクがそろう")
    func loadsDocumentAndBacklinks() async {
        let document = DocumentViewModel(
            path: "a.md",
            openDocument: OpenDocumentStub(sources: ["a.md": "---\ntags: [x]\nstatus: 下書き\n---\n# A"]),
            findBacklinks: FindBacklinksStub(backlinks: ["a.md": [NoteSummary(path: "b.md", title: "B")]])
        )

        await document.load()

        #expect(document.title == "A")
        #expect(document.tags == ["x"])
        #expect(document.properties.map(\.key) == ["tags", "status"])
        #expect(document.backlinks == [NoteSummary(path: "b.md", title: "B")])
        #expect(document.errorMessage == nil)
    }

    @Test("読めなければメッセージを出す")
    func showsErrorMessage() async {
        let document = DocumentViewModel(
            path: "ない.md", openDocument: OpenDocumentStub(), findBacklinks: FindBacklinksStub())

        await document.load()

        #expect(document.errorMessage == "ファイルが見つかりません。移動したか、削除された可能性があります。")
    }
}

@MainActor
@Suite("ナビゲータ")
struct NavigatorTests {
    @Test("木を読み、索引を作る。名前で絞り込める")
    func loadsTreeAndIndexes() async {
        let index = IndexVaultSpy()
        let navigator = FileNavigatorViewModel(
            loadTree: LoadTreeStub(),
            observeChanges: ObserveChangesStub(),
            indexVault: index
        )

        await navigator.reload()

        #expect(navigator.visibleNodes.map(\.name) == ["量子計算", "ホーム.md"])
        #expect(await index.count == 1)
        navigator.filterText = "ビット"
        #expect(navigator.visibleNodes.first?.children?.map(\.name) == ["量子ビット.md"])
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

// MARK: - テスト用の偽物

private struct ResolveLinkStub: ResolveLinkUseCase {
    let links: [String: String]
    func callAsFunction(_ target: String, exact: Bool) async throws(VaultError) -> String? { links[target] }
}

private struct OpenDocumentStub: OpenDocumentUseCase {
    var sources: [String: String] = [:]
    func callAsFunction(path: String) async throws(VaultError) -> Document {
        guard let source = sources[path] else { throw .fileNotFound(path: path) }
        return Document(
            path: path,
            name: path,
            kind: .markdown,
            info: FileInfo(path: path, size: source.utf8.count, created: nil, modified: .distantPast),
            content: .markdown(source: source, analysis: MarkdownAnalyzer.analyze(source, path: path))
        )
    }
}

private struct FindBacklinksStub: FindBacklinksUseCase {
    var backlinks: [String: [NoteSummary]] = [:]
    func callAsFunction(to path: String) async throws -> [NoteSummary] { backlinks[path] ?? [] }
}

private struct LoadTreeStub: LoadVaultTreeUseCase {
    func callAsFunction() async throws(VaultError) -> VaultNode {
        VaultNode(
            id: "",
            name: "Vault",
            kind: .folder,
            children: [
                VaultNode(id: "ホーム.md", name: "ホーム.md", kind: .markdown),
                VaultNode(
                    id: "量子計算",
                    name: "量子計算",
                    kind: .folder,
                    children: [VaultNode(id: "量子計算/量子ビット.md", name: "量子ビット.md", kind: .markdown)]
                ),
            ]
        )
    }
}

private struct ObserveChangesStub: ObserveVaultChangesUseCase {
    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private actor IndexVaultSpy: IndexVaultUseCase {
    private(set) var count = 0
    func callAsFunction() async throws -> IndexSummary {
        count += 1
        return IndexSummary(total: 0, updated: 0, removed: 0)
    }
}

private struct SearchStub: SearchNotesUseCase {
    func callAsFunction(_ query: String) async throws -> [SearchResult] {
        [SearchResult(path: "固有値.md", title: "固有値", snippet: "…固有値…")]
    }
}

private struct TagsStub: ListTagsUseCase, FindNotesByTagUseCase {
    func callAsFunction() async throws -> [TagCount] { [TagCount(name: "量子計算", count: 1)] }
    func callAsFunction(_ tag: String) async throws -> [NoteSummary] {
        [NoteSummary(path: "量子計算/量子ビット.md", title: "量子ビット")]
    }
}

private struct ObserveIndexStub: ObserveNoteIndexUseCase {
    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
