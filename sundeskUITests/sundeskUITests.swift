//
//  sundeskUITests.swift
//  sundeskUITests
//
//  Created by 山田大陽 on 2026/09/29.
//

import XCTest

@MainActor
final class SundeskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // UI テストでは Python エンジンを起動しない（UserDefaults の引数ドメインで上書きする）
        app.launchArguments += ["-engine.startsAutomatically", "NO"]
        app.launch()
    }

    func testSidebarShowsAllDestinations() {
        let sidebar = app.outlines.firstMatch
        for title in ["ノート", "知識グラフ", "チャット", "実験室", "画像生成", "モデル"] {
            XCTAssertTrue(sidebar.staticTexts[title].waitForExistence(timeout: 5), "\(title) がサイドバーにない")
        }
    }

    func testSelectingDestinationShowsItsScreen() {
        app.outlines.firstMatch.staticTexts["知識グラフ"].click()

        XCTAssertTrue(app.staticTexts["フェーズ 2 で実装します。"].waitForExistence(timeout: 5))
    }

    func testEngineStatusIsShownInToolbar() {
        let button = app.toolbars.buttons["engine-status-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.value as? String, "停止中")
    }
}
