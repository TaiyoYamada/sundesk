//
//  sundeskUITests.swift
//  sundeskUITests
//
//  Created by 山田大陽 on 2026/09/29.
//

import XCTest

/// 研究ライブラリの見本（SampleLibrary の写し）を開いて、主な操作を確かめる。
@MainActor
final class SundeskUITests: XCTestCase {
    private var app: XCUIApplication!
    private var library: URL!

    private static let sampleLibrary = URL(filePath: #filePath)
        .deletingLastPathComponent()  // sundeskUITests
        .deletingLastPathComponent()  // sundesk
        .appending(path: "SampleLibrary", directoryHint: .isDirectory)

    override func setUp() async throws {
        continueAfterFailure = false
        // 見本を汚さないよう、写しを開く（取り込み箱の実行は、開いたときに実験へ移る）
        library = FileManager.default.temporaryDirectory.appending(path: "sundesk-uitest-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: Self.sampleLibrary, to: library)
        app = XCUIApplication()
        // UI テストでは Python エンジンを起動しない（UserDefaults の引数ドメインで上書きする）
        app.launchArguments += ["-engine.startsAutomatically", "NO", "-vault.directory", library.path]
        app.launch()
    }

    override func tearDown() async throws {
        app.terminate()
        if let library { try? FileManager.default.removeItem(at: library) }
    }

    private var fileTree: XCUIElement { app.outlines["file-tree"] }

    private func tabs() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "editor-tab")
    }

    private func expand(_ folder: String, in outline: XCUIElement) {
        let row = outline.outlineRows.containing(NSPredicate(format: "label == %@", folder)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(folder) がない")
        row.disclosureTriangles.firstMatch.click()
    }

    private func openFile(_ name: String, in outline: XCUIElement) {
        let row = outline.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) がナビゲータにない")
        row.click()
    }

    private func openLogNote() {
        expand("研究ログ", in: fileTree)
        openFile("2026-09-17.md", in: fileTree)
        XCTAssertTrue(app.textViews["text-editor"].waitForExistence(timeout: 10))
    }

    private func showSection(_ title: String) {
        let button = app.radioGroups["library-section"].radioButtons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(title) の切り替えがない")
        button.click()
    }

    private func attachWindowScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - ノート

    func testNavigatorShowsNotes() {
        XCTAssertTrue(fileTree.staticTexts["研究ログ"].waitForExistence(timeout: 10))
        for name in ["アイデア", "議事", "下書き"] {
            XCTAssertTrue(fileTree.staticTexts[name].exists, "\(name) がない")
        }
        attachWindowScreenshot(named: "ノート")
    }

    /// ノートはライブプレビュー（TextKit 2 のエディタ）で開く。
    func testOpeningNoteShowsEditor() {
        openLogNote()

        XCTAssertTrue(tabs().firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["text-editor"].value as? String)?.contains("やったこと") == true)
        XCTAssertEqual(app.toolbars.radioButtons["ライブプレビュー"].value as? Int, 1)
        attachWindowScreenshot(named: "ライブプレビュー")
    }

    /// ⌘E で閲覧（SwiftUI の整形表示）に切り替わり、もう一度押すと編集に戻る。
    func testTogglingReadingWithCommandE() {
        openLogNote()

        app.typeKey("e", modifierFlags: .command)

        XCTAssertTrue(app.descendants(matching: .any)["reading-view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["やったこと"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.toolbars.radioButtons["閲覧"].value as? Int, 1)
        attachWindowScreenshot(named: "閲覧")

        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["text-editor"].waitForExistence(timeout: 10))
    }

    /// ソースでは記号をすべて見せる。
    func testSourceMode() {
        openLogNote()

        app.toolbars.radioButtons["ソース"].click()

        XCTAssertEqual(app.toolbars.radioButtons["ソース"].value as? Int, 1)
        XCTAssertTrue((app.textViews["text-editor"].value as? String)?.contains("title: 2026-09-17") == true)
    }

    /// 実験へのリンクは題名で書いてあり、たどると実験のタブが開く。
    func testFollowingLinkToExperimentOpensExperimentTab() {
        openLogNote()
        app.typeKey("e", modifierFlags: .command)
        let link = app.links["SA"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))

        link.click()

        XCTAssertTrue(app.descendants(matching: .any)["experiment-screen"].waitForExistence(timeout: 10))
        XCTAssertEqual(tabs().count, 2)
        attachWindowScreenshot(named: "リンクから実験")
    }

    // MARK: - 論文、実験、資料

    func testOpeningPaper() {
        showSection("論文")
        let list = app.outlines["paper-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let paper = list.staticTexts["A variational eigenvalue solver on a photonic quantum processor"]
        XCTAssertTrue(paper.waitForExistence(timeout: 10))

        paper.click()

        XCTAssertTrue(app.descendants(matching: .any)["paper-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["PDF はありません"].exists)
        attachWindowScreenshot(named: "論文")
    }

    func testOpeningAndComparingExperiments() {
        showSection("実験")
        let list = app.outlines["experiment-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let saRow = list.staticTexts["SA で重みつき Max-Cut（30 頂点、GA と PSO と同じ評価の回数）"]
        let gaRow = list.staticTexts["GA で重みつき Max-Cut（30 頂点）"]
        XCTAssertTrue(saRow.waitForExistence(timeout: 10))

        saRow.click()
        XCTAssertTrue(app.descendants(matching: .any)["experiment-screen"].waitForExistence(timeout: 10))
        attachWindowScreenshot(named: "実験")

        gaRow.click()
        XCUIElement.perform(withKeyModifiers: .command) { saRow.click() }
        let compare = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '選んだ 2 件'")).firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        compare.click()

        XCTAssertTrue(app.descendants(matching: .any)["comparison-screen"].waitForExistence(timeout: 10))
        attachWindowScreenshot(named: "比べる")
    }

    /// 取り込み箱の実行は、開いたときに実験へ移る。
    func testInboxRunIsImported() {
        showSection("実験")
        let list = app.outlines["experiment-list"]
        XCTAssertTrue(
            list.staticTexts["SA の始めの温度を変える（Max-Cut 30 頂点、300 スイープ）"].waitForExistence(timeout: 15))
    }

    func testOpeningImageAndPDF() {
        showSection("資料")
        let list = app.outlines["file-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        openFile("maxcut-w30.png", in: list)
        XCTAssertTrue(app.images.firstMatch.waitForExistence(timeout: 5))
        attachWindowScreenshot(named: "画像")

        openFile("2026-09-24 進捗報告.pdf", in: list)
        XCTAssertEqual(tabs().count, 2)
        attachWindowScreenshot(named: "PDF")
    }

    // MARK: - 機能

    func testOpeningKnowledgeGraph() {
        app.buttons["知識グラフ"].firstMatch.click()

        let empty = app.staticTexts["知識グラフはまだありません"]
        let graph = app.descendants(matching: .any)["knowledge-graph"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5) || graph.exists)
        attachWindowScreenshot(named: "知識グラフ")
    }

    func testOpeningChat() {
        app.buttons["チャット"].firstMatch.click()

        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ノートに聞いてみましょう"].exists)
        attachWindowScreenshot(named: "チャット")
    }

    func testOpeningLabAndImages() {
        app.buttons["実験室"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["lab-prompt"].waitForExistence(timeout: 5))
        attachWindowScreenshot(named: "実験室")

        app.buttons["画像生成"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["image-prompt"].waitForExistence(timeout: 5))
        attachWindowScreenshot(named: "画像生成")
    }

    /// Xcode と同じく、⌘ と数字でナビゲータを切り替え、機能を開く。
    func testCommandNumberSwitchesNavigatorAndOpensTools() {
        XCTAssertTrue(fileTree.waitForExistence(timeout: 10))

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["search-field"].waitForExistence(timeout: 5))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(fileTree.waitForExistence(timeout: 5))

        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 5))
    }

    func testClosingTabWithCommandWKeepsWindow() {
        openLogNote()
        app.buttons["知識グラフ"].firstMatch.click()
        XCTAssertEqual(tabs().count, 2)

        app.typeKey("w", modifierFlags: .command)

        XCTAssertEqual(tabs().count, 1)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testEngineStatusIsShownInToolbar() {
        let button = app.toolbars.buttons["engine-status-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.value as? String, "停止中")
    }
}
