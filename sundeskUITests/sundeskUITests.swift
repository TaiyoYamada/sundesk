//
//  sundeskUITests.swift
//  sundeskUITests
//
//  Created by 山田大陽 on 2026/09/29.
//

import XCTest

/// 空のライブラリ（一時フォルダ）で起動して、主な操作を確かめる。通信する操作（識別子で足す）は確かめない。
@MainActor
final class SundeskUITests: XCTestCase {
    private var app: XCUIApplication!
    private var library: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        library = FileManager.default.temporaryDirectory.appending(path: "sundesk-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        app = XCUIApplication()
        // 本物のライブラリを汚さないよう、一時フォルダを使う（UserDefaults の引数ドメインで上書きする）
        app.launchArguments += ["-library.directory", library.path]
        app.launch()
    }

    override func tearDown() async throws {
        app.terminate()
        if let library { try? FileManager.default.removeItem(at: library) }
    }

    private func attachWindowScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEmptyLibraryShowsGuidance() {
        XCTAssertTrue(app.staticTexts["文献がありません"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["すべての文献"].exists)
        attachWindowScreenshot(named: "空のライブラリ")
    }

    /// ⇧⌘N で空の文献を足すと、一覧に出て、詳細で題名を書き換えられる。
    func testAddingBlankReferenceAndEditingTitle() {
        XCTAssertTrue(app.staticTexts["文献がありません"].waitForExistence(timeout: 10))

        app.typeKey("n", modifierFlags: [.command, .shift])

        let title = app.textFields["reference-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        // 日本語は typeText で打てないので、英語で確かめる。一覧（Table）は Outline として見える
        title.typeText("Variational eigensolver")
        XCTAssertTrue(app.outlines.staticTexts["Variational eigensolver"].waitForExistence(timeout: 10))
        attachWindowScreenshot(named: "文献の詳細")
    }

    func testCreatingCollection() {
        let button = app.buttons["新しいコレクション"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))

        button.click()
        // 名前を聞くアラートは Sheet として見える
        let name = app.sheets.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Optimization")
        app.sheets.buttons["OK"].click()

        XCTAssertTrue(app.outlines.staticTexts["Optimization"].waitForExistence(timeout: 10))
    }

    func testIdentifierSheetOpensWithCommandN() {
        XCTAssertTrue(app.staticTexts["文献がありません"].waitForExistence(timeout: 10))

        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(app.staticTexts["識別子で文献を足す"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.staticTexts["識別子で文献を足す"].waitForExistence(timeout: 2))
    }
}
