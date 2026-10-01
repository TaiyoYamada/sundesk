//
//  sundeskTests.swift
//  sundeskTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Testing

/// アプリ本体（入口だけ）のテスト。機能のテストは Packages/SundeskKit/Tests にある。
@Suite("アプリ本体")
struct AppBundleTests {
    @Test("バンドル ID と対象の OS")
    func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.taiyou.sundesk")
        #expect(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27)
    }
}
