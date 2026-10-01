//
//  EngineEnvironmentTests.swift
//  SundeskEngineClientTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Testing

@testable import SundeskEngineClient

@Suite("エンジンに渡す環境変数")
struct EngineEnvironmentTests {
    @Test(
        "Xcode のデバッグ実行で入る Metal の検証と差し込むライブラリは渡さない",
        arguments: [
            ("MTL_DEBUG_LAYER", true), ("METAL_DEVICE_WRAPPER_TYPE", true), ("DYLD_INSERT_LIBRARIES", true),
            ("__XPC_DYLD_INSERT_LIBRARIES", true), ("PATH", false), ("HOME", false), ("SUNDESK_MODELS_DIR", false),
        ])
    func dropsDebuggerOnlyVariables(key: String, dropped: Bool) {
        #expect(EngineProcess.isDebuggerOnly(key) == dropped)
    }
}
