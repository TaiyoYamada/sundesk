//
//  EngineRepositoryImpl.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import SundeskEngineClient

/// `EngineRepository` を、Python エンジンのプロセス管理（`EngineProcess`）で実装する。
public struct EngineRepositoryImpl: EngineRepository {
    private let process: EngineProcess

    public init(process: EngineProcess) {
        self.process = process
    }

    public func start() async throws(EngineFailure) {
        do {
            try await process.start()
        } catch {
            throw EngineMapper.failure(from: error)
        }
    }

    public func stop() async {
        await process.stop()
    }

    public func statusUpdates() async -> AsyncStream<EngineStatus> {
        let states = await process.states()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await state in states {
                    continuation.yield(EngineMapper.status(from: state))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
