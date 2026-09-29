//
//  EngineUseCaseTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import Testing

@Suite("エンジンの UseCase")
struct EngineUseCaseTests {
    @Test("起動は Repository の start に委ねる")
    func startDelegatesToRepository() async throws {
        let repository = EngineRepositorySpy()

        try await StartEngineInteractor(repository: repository)()

        #expect(await repository.startCount == 1)
    }

    @Test("起動の失敗はそのまま伝える")
    func startPropagatesFailure() async {
        let failure = EngineFailure(message: "uv が見つかりません")
        let repository = EngineRepositorySpy(startResult: .failure(failure))

        await #expect(throws: failure) {
            try await StartEngineInteractor(repository: repository)()
        }
    }

    @Test("停止は Repository の stop に委ねる")
    func stopDelegatesToRepository() async {
        let repository = EngineRepositorySpy()

        await StopEngineInteractor(repository: repository)()

        #expect(await repository.stopCount == 1)
    }

    @Test("状態の監視は Repository の流す状態をそのまま返す")
    func observeReturnsRepositoryStream() async {
        let info = EngineInfo(version: "0.1.0", pythonVersion: "3.13.7")
        let repository = EngineRepositorySpy(statuses: [.stopped, .starting, .running(info)])

        var received: [EngineStatus] = []
        for await status in await ObserveEngineStatusInteractor(repository: repository)() {
            received.append(status)
        }

        #expect(received == [.stopped, .starting, .running(info)])
    }
}

@Suite("EngineStatus")
struct EngineStatusTests {
    @Test(
        "isRunning は稼働中のときだけ true",
        arguments: [
            (EngineStatus.stopped, false),
            (.starting, false),
            (.running(EngineInfo(version: "0.1.0", pythonVersion: "3.13.7")), true),
            (.failed(EngineFailure(message: "x")), false),
        ]
    )
    func isRunning(status: EngineStatus, expected: Bool) {
        #expect(status.isRunning == expected)
    }
}

private actor EngineRepositorySpy: EngineRepository {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let startResult: Result<Void, EngineFailure>
    private let statuses: [EngineStatus]

    init(startResult: Result<Void, EngineFailure> = .success(()), statuses: [EngineStatus] = []) {
        self.startResult = startResult
        self.statuses = statuses
    }

    func start() async throws(EngineFailure) {
        startCount += 1
        try startResult.get()
    }

    func stop() async {
        stopCount += 1
    }

    func statusUpdates() async -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            for status in statuses { continuation.yield(status) }
            continuation.finish()
        }
    }
}
