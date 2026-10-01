//
//  DocumentViewModelTests.swift
//  NotesFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import NotesFeature
import SundeskDomain
import Testing

@MainActor
@Suite("DocumentViewModel")
struct DocumentViewModelTests {
    private static let analysis = NoteAnalysis(
        title: "A",
        properties: [
            NoteProperty(key: "title", value: .text("A")),
            NoteProperty(key: "status", value: .text("下書き")),
            NoteProperty(key: "tags", value: .list(["x"])),
        ],
        tags: ["x"],
        links: [],
        headings: [NoteHeading(level: 1, text: "A", line: 5), NoteHeading(level: 2, text: "節", line: 7)],
        body: "# A"
    )

    private static let vaultRoot = URL(filePath: "/vault")

    private func makeDocument(
        _ path: String,
        documents: [String: Document] = [:],
        open: (any OpenDocumentUseCase)? = nil,
        save: SaveDocumentSpy = SaveDocumentSpy(),
        backlinks: [String: [NoteSummary]] = [:],
        autosaveDelay: Duration = .seconds(60)
    ) -> DocumentViewModel {
        DocumentViewModel(
            path: path,
            openDocument: open ?? OpenDocumentStub(documents: documents),
            saveDocument: save,
            analyzeNote: AnalyzeNoteStub(),
            findBacklinks: FindBacklinksStub(backlinks: backlinks),
            locateFile: LocateFileStub(),
            autosaveDelay: autosaveDelay
        )
    }

    private func markdownDocument(source: String = "# A", save: SaveDocumentSpy = SaveDocumentSpy()) async
        -> DocumentViewModel
    {
        let document = makeDocument(
            "a.md", documents: ["a.md": OpenDocumentStub.markdown("a.md", source: source, analysis: Self.analysis)],
            save: save)
        await document.load()
        return document
    }

    // MARK: - 表示

    @Test("読み込む前は読み込み中、読めなければメッセージを出す")
    func loadingAndFailure() async {
        let document = makeDocument("ない.md")
        #expect(document.display == .loading)

        await document.load()

        #expect(document.display == .failed(message: "ファイルが見つかりません。移動したか、削除された可能性があります。"))
    }

    @Test("Markdown はライブプレビューで開き、ソースと閲覧に切り替えられる")
    func markdownModes() async {
        let document = await markdownDocument()

        #expect(document.availableModes == [.livePreview, .source, .reading])
        #expect(document.display == .markdownEditor(livePreview: true))
        #expect(document.text == "# A")

        document.displayMode = .source
        #expect(document.display == .markdownEditor(livePreview: false))
        document.displayMode = .reading
        #expect(document.display == .markdownReading(vaultRoot: Self.vaultRoot))
    }

    @Test("⌘E は編集と閲覧を行き来し、前に使っていた編集のモードに戻る")
    func toggleReturnsToLastEditingMode() async {
        let document = await markdownDocument()
        document.displayMode = .source

        document.toggleDisplayMode()
        #expect(document.displayMode == .reading)
        document.toggleDisplayMode()
        #expect(document.displayMode == .source)
    }

    @Test("HTML は閲覧とソース、コードは色づけのエディタ、画像は切り替えなし")
    func otherKinds() async {
        let html = makeDocument(
            "a.html",
            documents: [
                "a.html": OpenDocumentStub.file(
                    "a.html", kind: .html, content: .html(source: "<p>", url: URL(filePath: "/vault/a.html")))
            ])
        let code = makeDocument(
            "a.swift",
            documents: [
                "a.swift": OpenDocumentStub.file(
                    "a.swift", kind: .code(language: "swift"), content: .text(source: "let a = 1"))
            ])
        let text = makeDocument(
            "a.txt", documents: ["a.txt": OpenDocumentStub.file("a.txt", kind: .text, content: .text(source: "メモ"))])
        let image = makeDocument("a.png")
        await html.load()
        await code.load()
        await text.load()

        #expect(html.availableModes == [.reading, .source])
        #expect(html.display == .htmlPage(vaultRoot: Self.vaultRoot))
        html.toggleDisplayMode()
        #expect(html.display == .codeEditor(language: "html"))

        #expect(!code.canToggleDisplayMode)
        #expect(code.display == .codeEditor(language: "swift"))
        #expect(text.display == .codeEditor(language: nil))
        #expect(!image.canToggleDisplayMode)
        #expect(!image.isEditable)
    }

    @Test("ノートブックは閲覧でセルを並べ、ソースでは JSON を読むだけにする")
    func notebook() async {
        let notebook = Notebook(
            language: "python", cells: [.markdown("# A"), .code(source: "1", executionCount: 1, outputs: [.text("1")])])
        let document = makeDocument(
            "a.ipynb",
            documents: [
                "a.ipynb": OpenDocumentStub.file(
                    "a.ipynb", kind: .notebook, content: .notebook(source: "{}", notebook: notebook))
            ])
        await document.load()

        #expect(document.availableModes == [.reading, .source])
        guard case .notebook(let item, _) = document.display else {
            Issue.record("ノートブックとして描いていない")
            return
        }
        #expect(item.cells.count == 2)
        #expect(item.cells[1].kind == .code(source: "1", executionCount: 1, outputs: [.text("1")]))
        #expect(!document.isEditable)
        document.toggleDisplayMode()
        #expect(document.display == .codeEditor(language: "json"))
    }

    // MARK: - インスペクタ

    @Test("インスペクタ: プロパティ（タイトルとタグを除く）、タグ、目次、バックリンク")
    func inspectorItems() async {
        let document = makeDocument(
            "a.md",
            documents: ["a.md": OpenDocumentStub.markdown("a.md", source: "# A", analysis: Self.analysis)],
            backlinks: ["a.md": [NoteSummary(path: "b.md", title: "B")]]
        )

        await document.load()

        #expect(document.properties.map(\.key) == ["status"])
        #expect(document.properties.map(\.value) == ["下書き"])
        #expect(document.tags == ["x"])
        #expect(document.outline.map(\.title) == ["A", "節"])
        #expect(document.outline.map(\.line) == [5, 7])
        #expect(document.backlinks.map(\.path) == ["b.md"])
        #expect(document.fileInfo?.kind == "Markdown")
        #expect(document.fileURL == URL(filePath: "/vault/a.md"))
    }

    @Test("編集すると、目次が書いたそばから変わる")
    func reanalyzesWhileEditing() async {
        let document = await markdownDocument()

        document.text = "# 新しい題\n\n## 一\n## 二"

        #expect(document.outline.map(\.title) == ["新しい題", "一", "二"])
        #expect(document.outline.map(\.line) == [1, 3, 4])
    }

    // MARK: - 保存

    @Test("編集すると少し待ってから自動で保存する")
    func autosaves() async throws {
        let save = SaveDocumentSpy()
        let document = makeDocument(
            "a.md", documents: ["a.md": OpenDocumentStub.markdown("a.md", source: "# A", analysis: Self.analysis)],
            save: save, autosaveDelay: .milliseconds(20))
        await document.load()

        document.text = "# A\n追記"
        #expect(document.saveState == .unsaved)
        #expect(document.hasUnsavedChanges)

        try await waitUntil { document.saveState == .saved }
        #expect(await save.saved.map(\.text) == ["# A\n追記"])
        #expect(await save.saved.map(\.path) == ["a.md"])
        #expect(!document.hasUnsavedChanges)
    }

    @Test("続けて編集すると、保存は最後の 1 回にまとまる")
    func debouncesSaves() async throws {
        let save = SaveDocumentSpy()
        let document = makeDocument(
            "a.md", documents: ["a.md": OpenDocumentStub.markdown("a.md", source: "", analysis: Self.analysis)],
            save: save, autosaveDelay: .milliseconds(50))
        await document.load()

        for text in ["あ", "あい", "あいう"] {
            document.text = text
        }

        try await waitUntil { document.saveState == .saved }
        #expect(await save.saved.map(\.text) == ["あいう"])
    }

    @Test("flush は待たずに保存し、変更がなければ保存しない")
    func flushSavesImmediately() async {
        let save = SaveDocumentSpy()
        let document = await markdownDocument(save: save)

        await document.flush()
        #expect(await save.saved.isEmpty)

        document.text = "# B"
        await document.flush()
        #expect(await save.saved.map(\.text) == ["# B"])
        #expect(document.saveState == .saved)
    }

    @Test("保存に失敗したら知らせ、もう一度保存できる")
    func reportsSaveFailure() async {
        let save = SaveDocumentSpy()
        await save.fail(with: .unwritable(path: "a.md", reason: "ディスクがいっぱい"))
        let document = await markdownDocument(save: save)

        document.text = "# B"
        await document.flush()
        #expect(document.saveState == .failed(message: "ファイルを保存できませんでした: ディスクがいっぱい"))
        #expect(document.hasUnsavedChanges)

        await save.fail(with: nil)
        await document.flush()
        #expect(document.saveState == .saved)
        #expect(await save.saved.map(\.text) == ["# B"])
    }

    @Test("ファイルが外で書き換えられたら読み直す。編集中なら画面の本文を残す")
    func externalChanges() async {
        let open = MutableOpenDocumentStub(OpenDocumentStub.markdown("a.md", source: "# A", analysis: Self.analysis))
        let document = makeDocument("a.md", open: open)
        await document.load()

        open.document = OpenDocumentStub.markdown("a.md", source: "# 外で変更", analysis: Self.analysis)
        await document.load()
        #expect(document.text == "# 外で変更")

        document.text = "# 画面で編集"
        open.document = OpenDocumentStub.markdown("a.md", source: "# また外で変更", analysis: Self.analysis)
        await document.load()
        #expect(document.text == "# 画面で編集")
    }

    @Test("画像など、編集できないファイルの本文は変えられない")
    func nonEditableIgnoresText() async {
        let document = makeDocument(
            "a.png",
            documents: [
                "a.png": OpenDocumentStub.file("a.png", kind: .image, content: .image(URL(filePath: "/vault/a.png")))
            ])
        await document.load()

        document.text = "x"

        #expect(document.text.isEmpty)
        #expect(document.saveState == .saved)
    }

    /// 条件が満たされるまで待つ（最大 2 秒）。
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
