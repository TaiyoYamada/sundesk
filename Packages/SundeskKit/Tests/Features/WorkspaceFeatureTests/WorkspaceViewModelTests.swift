//
//  WorkspaceViewModelTests.swift
//  WorkspaceFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import LibraryFeature
import NotesFeature
import SundeskDomain
import Testing
import WorkspaceFeature

@Suite("WorkspaceViewModel")
struct WorkspaceViewModelTests {
    private func makeWorkspace(links: [String: String] = [:]) -> WorkspaceViewModel {
        WorkspaceViewModel(resolveLink: ResolveLinkStub(links: links)) { path in
            DocumentViewModel(
                path: path, openDocument: OpenDocumentStub(), saveDocument: SaveDocumentStub(),
                analyzeNote: AnalyzeNoteStub(), findBacklinks: FindBacklinksStub(), locateFile: LocateFileStub())
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

        workspace.open(tool: .graph)

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

    @Test("論文や実験のメモへのリンクは、論文や実験の画面で開き、読めた題名をタブに出す")
    func opensLibraryScreensFromLinks() async {
        let workspace = makeWorkspace(links: ["SA の実験": "Experiments/2026-09-17-sa/note.md"])

        await workspace.openLink("SA の実験", isExactPath: false)
        #expect(workspace.selectedTab?.content == .experiment("2026-09-17-sa"))
        workspace.open(path: "Papers/peruzzo2014/paper.pdf")
        #expect(workspace.selectedTab?.content == .paper("peruzzo2014"))
        workspace.open(path: "Experiments/2026-09-17-sa/note.md", line: 3)
        #expect(workspace.tabs.count == 2)

        workspace.retitle(.experiment("2026-09-17-sa"), to: "SA で Max-Cut")
        #expect(workspace.tabs.first { $0.content == .experiment("2026-09-17-sa") }?.title == "SA で Max-Cut")
    }

    @Test("出典から論文の PDF を開くと、そのページを頼む。頼むたびに別の頼みになる")
    func requestsPDFPage() {
        let workspace = makeWorkspace()

        workspace.open(path: "Papers/peruzzo2014/paper.pdf", line: 3)
        let first = workspace.pageRequests["peruzzo2014"]
        #expect(first?.page == 3)
        #expect(workspace.selectedTab?.content == .paper("peruzzo2014"))

        workspace.open(path: "Papers/peruzzo2014/paper.pdf", line: 3)
        #expect(workspace.pageRequests["peruzzo2014"] != first)
        #expect(workspace.tabs.count == 1)
    }

    @Test("タブの名前とアイコン。Markdown は拡張子を出さない")
    func tabTitles() {
        #expect(WorkspaceTab(content: .document("論文メモ/Attention.md")).title == "Attention")
        #expect(WorkspaceTab(content: .document("資料/図.png")).title == "図.png")
        #expect(WorkspaceTab(content: .document("資料/図.png")).systemImage == "photo")
        #expect(WorkspaceTab(content: .tool(.chat)).title == "チャット")
    }

    @Test("機能はすべて名前とアイコンを持つ", arguments: WorkspaceTool.allCases)
    func toolsHaveTitleAndSymbol(tool: WorkspaceTool) {
        #expect(!tool.title.isEmpty)
        #expect(!tool.systemImage.isEmpty)
    }
}

// MARK: - テスト用の偽物

private struct ResolveLinkStub: ResolveLinkUseCase {
    let links: [String: String]
    func callAsFunction(_ target: String, exact: Bool) async throws(VaultError) -> String? { links[target] }
}

private struct OpenDocumentStub: OpenDocumentUseCase {
    func callAsFunction(path: String) async throws(VaultError) -> Document { throw .fileNotFound(path: path) }
}

private struct SaveDocumentStub: SaveDocumentUseCase {
    func callAsFunction(_ text: String, to path: String) async throws(VaultError) {}
}

private struct AnalyzeNoteStub: AnalyzeNoteUseCase {
    func callAsFunction(_ source: String, path: String) -> NoteAnalysis {
        NoteAnalysis(title: nil, properties: [], tags: [], links: [], body: source)
    }
}

private struct FindBacklinksStub: FindBacklinksUseCase {
    func callAsFunction(to path: String) async throws(NoteIndexError) -> [NoteSummary] { [] }
}

private struct LocateFileStub: LocateFileUseCase {
    func callAsFunction(_ path: String) -> URL { URL(filePath: "/vault").appending(path: path) }
    func vaultRoot() -> URL { URL(filePath: "/vault") }
}
