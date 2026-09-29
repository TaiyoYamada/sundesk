//
//  sundeskTests.swift
//  sundeskTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import Testing

@testable import sundesk

@MainActor
@Suite("エンジンの状態の表示")
struct EngineIndicatorStyleTests {
    @Test("状態ごとに別のアイコンを使う")
    func symbolsAreDistinct() {
        let symbols = [
            EngineStatusViewModel.Indicator.idle, .working, .ready, .error,
        ].map(\.symbolName)

        #expect(Set(symbols).count == symbols.count)
    }
}
