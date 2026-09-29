//
//  sundeskUITests.swift
//  sundeskUITests
//
//  Created by 山田大陽 on 2026/09/29.
//

import XCTest

/// モックの SampleVault を開いて、主な操作を確かめる。
@MainActor
final class SundeskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // UI テストでは Python エンジンを起動しない（UserDefaults の引数ドメインで上書きする）
        app.launchArguments += ["-engine.startsAutomatically", "NO", "-vault.directory", ""]
        app.launch()
    }

    private var fileTree: XCUIElement { app.outlines["file-tree"] }

    private func openFile(_ name: String) {
        let row = fileTree.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) がナビゲータにない")
        row.click()
    }

    private func attachWindowScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNavigatorShowsSampleVault() {
        XCTAssertTrue(fileTree.staticTexts["ホーム.md"].waitForExistence(timeout: 10))
        for name in ["量子計算", "数学", "Swift", "資料"] {
            XCTAssertTrue(fileTree.staticTexts[name].exists, "\(name) がない")
        }
    }

    /// ノートはライブプレビュー（TextKit 2 のエディタ）で開く。
    func testOpeningNoteShowsEditor() {
        openFile("ホーム.md")

        XCTAssertTrue(app.descendants(matching: .any)["editor-tab"].waitForExistence(timeout: 5))
        let editor = app.textViews["text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue((editor.value as? String)?.contains("いま追いかけていること") == true)
        XCTAssertEqual(app.toolbars.radioButtons["ライブプレビュー"].value as? Int, 1)
        attachWindowScreenshot(named: "ライブプレビュー")
    }

    /// ⌘E で閲覧（SwiftUI の整形表示）に切り替わり、もう一度押すと編集に戻る。
    func testTogglingReadingWithCommandE() {
        openFile("ホーム.md")
        XCTAssertTrue(app.textViews["text-editor"].waitForExistence(timeout: 10))

        app.typeKey("e", modifierFlags: .command)

        XCTAssertTrue(app.descendants(matching: .any)["reading-view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["いま追いかけていること"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.toolbars.radioButtons["閲覧"].value as? Int, 1)
        attachWindowScreenshot(named: "閲覧")

        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["text-editor"].waitForExistence(timeout: 10))
    }

    /// ソースでは記号をすべて見せる。
    func testSourceMode() {
        openFile("ホーム.md")
        XCTAssertTrue(app.textViews["text-editor"].waitForExistence(timeout: 10))

        app.toolbars.radioButtons["ソース"].click()

        XCTAssertEqual(app.toolbars.radioButtons["ソース"].value as? Int, 1)
        XCTAssertTrue((app.textViews["text-editor"].value as? String)?.contains("title: ホーム") == true)
        attachWindowScreenshot(named: "ソース")
    }

    func testFollowingWikilinkInReadingViewOpensNewTab() {
        openFile("ホーム.md")
        XCTAssertTrue(app.textViews["text-editor"].waitForExistence(timeout: 10))
        app.typeKey("e", modifierFlags: .command)
        let link = app.links["並行処理"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))

        link.click()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "editor-tab").element(boundBy: 1).waitForExistence(
                timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "editor-tab").count, 2)
    }

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

    func testClosingTabWithCommandWKeepsWindow() {
        openFile("ホーム.md")
        app.buttons["知識グラフ"].firstMatch.click()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "editor-tab").count, 2)

        app.typeKey("w", modifierFlags: .command)

        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "editor-tab").count, 1)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testOpeningImageAndPDF() {
        let folder = fileTree.outlineRows.containing(NSPredicate(format: "label == '資料'")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.disclosureTriangles.firstMatch.click()

        openFile("bloch-sphere.png")
        XCTAssertTrue(app.images.firstMatch.waitForExistence(timeout: 5))
        attachWindowScreenshot(named: "画像")

        openFile("量子計算の講義スライド.pdf")
        attachWindowScreenshot(named: "PDF")
    }

    func testEngineStatusIsShownInToolbar() {
        let button = app.toolbars.buttons["engine-status-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.value as? String, "停止中")
    }
}
