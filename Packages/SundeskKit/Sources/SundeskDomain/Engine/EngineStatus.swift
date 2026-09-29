//
//  EngineStatus.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

/// AI エンジン（LLM、画像生成、埋め込みなどの計算を担う別プロセス）の状態。
public enum EngineStatus: Sendable, Equatable {
    case stopped
    case starting
    case running(EngineInfo)
    case failed(EngineFailure)

    public var isRunning: Bool {
        if case .running = self { true } else { false }
    }
}

/// 起動しているエンジンの情報。
public struct EngineInfo: Sendable, Equatable {
    public let version: String
    public let pythonVersion: String

    public init(version: String, pythonVersion: String) {
        self.version = version
        self.pythonVersion = pythonVersion
    }
}

/// エンジンを起動できなかった、または途中で止まった理由。
public struct EngineFailure: Error, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
