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
        let library = FileManager.default.temporaryDirectory.appending(path: "sundesk-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: library) }
        let app = XCUIApplication()
        app.launchArguments += ["-library.directory", library.path]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "起動直後の画面"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
