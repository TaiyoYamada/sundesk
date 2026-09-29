//
//  EngineStatusViewModelTests.swift
//  SundeskPresentationTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import SundeskPresentation
import Testing

@MainActor
@Suite("EngineStatusViewModel")
struct EngineStatusViewModelTests {
    nonisolated private static let info = EngineInfo(version: "0.1.0", pythonVersion: "3.13.7")

    @Test("監視すると、流れてきた最後の状態が表示される")
    func observeUpdatesStatus() async {
        let viewModel = makeViewModel(statuses: [.starting, .running(Self.info)])

        await viewModel.observe()

        #expect(viewModel.status == .running(Self.info))
        #expect(viewModel.detail == "sundesk-engine 0.1.0・Python 3.13.7")
    }

    @Test("起動に失敗すると、メッセージを lastError に残す")
    func startFailureSetsLastError() async {
        let viewModel = makeViewModel(startResult: .failure(EngineFailure(message: "uv が見つかりません")))

        await viewModel.start()

        #expect(viewModel.lastError == "uv が見つかりません")
    }

    @Test("次の操作を始めると、前のエラーは消える")
    func nextActionClearsLastError() async {
        let viewModel = makeViewModel(startResult: .failure(EngineFailure(message: "失敗")))
        await viewModel.start()

        await viewModel.stop()

        #expect(viewModel.lastError == nil)
    }

    @Test(
        "状態ごとの表示と、押せるボタン",
        arguments: [
            (EngineStatus.stopped, EngineStatusViewModel.Indicator.idle, "停止中", true, false),
            (.starting, .working, "起動中…", false, true),
            (.running(info), .ready, "稼働中", false, true),
            (.failed(EngineFailure(message: "x")), .error, "エラー", true, false),
        ]
    )
    func presentation(
        status: EngineStatus,
        indicator: EngineStatusViewModel.Indicator,
        title: String,
        canStart: Bool,
        canStop: Bool
    ) async {
        let viewModel = makeViewModel(statuses: [status])
        await viewModel.observe()

        #expect(viewModel.indicator == indicator)
        #expect(viewModel.title == title)
        #expect(viewModel.canStart == canStart)
        #expect(viewModel.canStop == canStop)
    }

    private func makeViewModel(
        startResult: Result<Void, EngineFailure> = .success(()),
        statuses: [EngineStatus] = []
    ) -> EngineStatusViewModel {
        EngineStatusViewModel(
            startEngine: StartEngineStub(result: startResult),
            stopEngine: StopEngineStub(),
            observeStatus: ObserveEngineStatusStub(statuses: statuses)
        )
    }
}

private struct StartEngineStub: StartEngineUseCase {
    let result: Result<Void, EngineFailure>
    func callAsFunction() async throws(EngineFailure) { try result.get() }
}

private struct StopEngineStub: StopEngineUseCase {
    func callAsFunction() async {}
}

private struct ObserveEngineStatusStub: ObserveEngineStatusUseCase {
    let statuses: [EngineStatus]
    func callAsFunction() async -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            for status in statuses { continuation.yield(status) }
            continuation.finish()
        }
    }
}
