//
//  sundeskUITestsLaunchTests.swift
//  sundeskUITests
//
//  Created by 山田大陽 on 2026/09/29.
//

import XCTest

/// ライトモードとダークモードで起動し、最初の画面のスクリーンショットを残す。
final class SundeskUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-engine.startsAutomatically", "NO"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "起動直後の画面"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
