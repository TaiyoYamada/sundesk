//
//  EngineUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

// MARK: - 起動

public protocol StartEngineUseCase: Sendable {
    func callAsFunction() async throws(EngineFailure)
}

public struct StartEngineInteractor: StartEngineUseCase {
    private let repository: any EngineRepository

    public init(repository: any EngineRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws(EngineFailure) {
        try await repository.start()
    }
}

// MARK: - 停止

public protocol StopEngineUseCase: Sendable {
    func callAsFunction() async
}

public struct StopEngineInteractor: StopEngineUseCase {
    private let repository: any EngineRepository

    public init(repository: any EngineRepository) {
        self.repository = repository
    }

    public func callAsFunction() async {
        await repository.stop()
    }
}

// MARK: - 状態の監視

public protocol ObserveEngineStatusUseCase: Sendable {
    func callAsFunction() async -> AsyncStream<EngineStatus>
}

public struct ObserveEngineStatusInteractor: ObserveEngineStatusUseCase {
    private let repository: any EngineRepository

    public init(repository: any EngineRepository) {
        self.repository = repository
    }

    public func callAsFunction() async -> AsyncStream<EngineStatus> {
        await repository.statusUpdates()
    }
}
