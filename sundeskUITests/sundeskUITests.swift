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

    func testOpeningNoteShowsTabAndRenderedContent() {
        openFile("ホーム.md")

        XCTAssertTrue(app.descendants(matching: .any)["editor-tab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["いま追いかけていること"].waitForExistence(timeout: 10))
        attachWindowScreenshot(named: "ノートを開いた画面")
    }

    func testTogglingSourceWithCommandE() {
        openFile("ホーム.md")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["いま追いかけていること"].waitForExistence(timeout: 10))

        app.typeKey("e", modifierFlags: .command)

        let frontmatter = app.webViews.firstMatch.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'title: ホーム'"))
        XCTAssertTrue(frontmatter.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.toolbars.radioButtons["ソース"].value as? Int, 1)
        attachWindowScreenshot(named: "ソース表示")
    }

    func testFollowingWikilinkOpensNewTab() {
        openFile("ホーム.md")
        let link = app.webViews.firstMatch.links["並行処理"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))

        link.click()

        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Swift の並行処理"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "editor-tab").count, 2)
    }

    func testOpeningFeatureOpensTab() {
        app.buttons["知識グラフ"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["フェーズ 2 で実装します。"].waitForExistence(timeout: 5))
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
