//
//  EngineMapperTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SundeskEngine
import Testing

@testable import SundeskData

@Suite("EngineMapper")
struct EngineMapperTests {
    @Test("プロセスの状態を Domain の状態に変換する")
    func mapsProcessStateToDomainStatus() {
        let health = EngineHealth(status: "ok", version: "0.1.0", pythonVersion: "3.13.7")

        #expect(EngineMapper.status(from: .stopped) == .stopped)
        #expect(EngineMapper.status(from: .starting) == .starting)
        #expect(
            EngineMapper.status(from: .running(health))
                == .running(EngineInfo(version: "0.1.0", pythonVersion: "3.13.7"))
        )
    }

    @Test(
        "エラーを、利用者が次にすべきことの分かる日本語に変換する",
        arguments: [
            (EngineProcessError.uvNotFound(path: "/x/uv"), "uv"),
            (.engineDirectoryNotFound(path: "/x/engine"), "pyproject.toml"),
            (.portUnavailable, "ポート"),
            (.launchFailed("理由"), "理由"),
            (.terminated(detail: "終了コード: 1"), "終了コード: 1"),
            (.timedOut, "時間内に応答"),
        ]
    )
    func mapsErrorsToMessages(error: EngineProcessError, expectedFragment: String) {
        #expect(EngineMapper.failure(from: error).message.contains(expectedFragment))
    }
}

@Suite("EngineRepositoryImpl")
struct EngineRepositoryImplTests {
    @Test("起動の失敗は EngineFailure に変換して伝える")
    func startMapsFailure() async {
        let process = EngineProcess(configuration: {
            EngineConfiguration(
                engineDirectory: URL(filePath: "/nonexistent/engine"),
                uvExecutable: URL(filePath: "/nonexistent/uv")
            )
        })
        let repository = EngineRepositoryImpl(process: process)

        await #expect {
            try await repository.start()
        } throws: { error in
            (error as? EngineFailure)?.message.contains("uv が見つかりません") == true
        }
    }

    @Test("状態の監視では、まず現在の状態が届く")
    func statusUpdatesStartWithCurrentState() async {
        let process = EngineProcess(configuration: {
            EngineConfiguration(engineDirectory: URL(filePath: "/x"), uvExecutable: URL(filePath: "/x"))
        })
        let repository = EngineRepositoryImpl(process: process)

        var iterator = await repository.statusUpdates().makeAsyncIterator()

        #expect(await iterator.next() == .stopped)
    }
}
