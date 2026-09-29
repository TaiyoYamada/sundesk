//
//  EngineProcessTests.swift
//  SundeskEngineTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskEngine
import Testing

extension Tag {
    /// 本物の uv と Python エンジンを起動するテスト。`SUNDESK_INTEGRATION=1` のときだけ走る。
    @Tag static var integration: Self
}

@Suite("EngineProcess")
struct EngineProcessTests {
    @Test("監視を始めると、最初に現在の状態が届く")
    func statesYieldsCurrentStateFirst() async {
        let process = EngineProcess(configuration: { .missingEverything })

        var iterator = await process.states().makeAsyncIterator()

        #expect(await iterator.next() == .stopped)
    }

    @Test("uv が見つからなければ、起動せずに失敗する")
    func startFailsWithoutUV() async {
        let process = EngineProcess(configuration: { .missingEverything })

        await #expect(throws: EngineProcessError.uvNotFound(path: "/nonexistent/uv")) {
            try await process.start()
        }
        #expect(await process.state == .failed(.uvNotFound(path: "/nonexistent/uv")))
    }

    @Test("エンジンのフォルダに pyproject.toml がなければ失敗する")
    func startFailsWithoutEngineDirectory() async {
        let configuration = EngineConfiguration(
            engineDirectory: URL(filePath: "/nonexistent/engine"),
            uvExecutable: URL(filePath: "/bin/sh")
        )
        let process = EngineProcess(configuration: { configuration })

        await #expect(throws: EngineProcessError.engineDirectoryNotFound(path: "/nonexistent/engine")) {
            try await process.start()
        }
    }

    @Test("止まっているときの stop は何もしない")
    func stopWhenStoppedIsNoOp() async {
        let process = EngineProcess(configuration: { .missingEverything })

        await process.stop()

        #expect(await process.state == .stopped)
    }

    @Test(
        "本物のエンジンを起動し、応答を確かめてから止める",
        .tags(.integration),
        .enabled(if: ProcessInfo.processInfo.environment["SUNDESK_INTEGRATION"] == "1"),
        .timeLimit(.minutes(5))
    )
    func startsAndStopsRealEngine() async throws {
        let uv = try #require(EngineLocator.findUV())
        let configuration = EngineConfiguration(
            engineDirectory: EngineLocator.defaultEngineDirectory(),
            uvExecutable: uv
        )
        let process = EngineProcess(configuration: { configuration })

        try await process.start()
        guard case .running(let health) = await process.state else {
            Issue.record("起動後の状態が running ではない: \(await process.state)")
            return
        }
        #expect(health.status == "ok")

        await process.stop()
        #expect(await process.state == .stopped)
    }
}

extension EngineConfiguration {
    fileprivate static let missingEverything = EngineConfiguration(
        engineDirectory: URL(filePath: "/nonexistent/engine"),
        uvExecutable: URL(filePath: "/nonexistent/uv")
    )
}
