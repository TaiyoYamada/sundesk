//
//  EngineStatusViewModel.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Observation
import SundeskDomain

/// ツールバーと設定画面に出す、AI エンジンの状態。
@MainActor
@Observable
public final class EngineStatusViewModel {
    /// 状態を表す印。色やアイコンへの対応づけは View に任せる。
    public enum Indicator: Sendable {
        case idle
        case working
        case ready
        case error
    }

    public private(set) var status: EngineStatus = .stopped
    /// 最後に失敗した操作のメッセージ。次の操作を始めると消える。
    public private(set) var lastError: String?

    @ObservationIgnored private let startEngine: any StartEngineUseCase
    @ObservationIgnored private let stopEngine: any StopEngineUseCase
    @ObservationIgnored private let observeStatus: any ObserveEngineStatusUseCase

    public init(
        startEngine: any StartEngineUseCase,
        stopEngine: any StopEngineUseCase,
        observeStatus: any ObserveEngineStatusUseCase
    ) {
        self.startEngine = startEngine
        self.stopEngine = stopEngine
        self.observeStatus = observeStatus
    }

    /// 状態の変化を追い続ける。View の `.task` から呼び、View が消えると止まる。
    public func observe() async {
        for await status in await observeStatus() {
            self.status = status
        }
    }

    public func start() async {
        lastError = nil
        do {
            try await startEngine()
        } catch {
            lastError = error.message
        }
    }

    public func stop() async {
        lastError = nil
        await stopEngine()
    }

    // MARK: - 表示

    public var indicator: Indicator {
        switch status {
        case .stopped: .idle
        case .starting: .working
        case .running: .ready
        case .failed: .error
        }
    }

    public var title: String {
        switch status {
        case .stopped: "停止中"
        case .starting: "起動中…"
        case .running: "稼働中"
        case .failed: "エラー"
        }
    }

    public var detail: String? {
        switch status {
        case .stopped, .starting: nil
        case .running(let info): "sundesk-engine \(info.version)・Python \(info.pythonVersion)"
        case .failed(let failure): failure.message
        }
    }

    public var canStart: Bool {
        switch status {
        case .stopped, .failed: true
        case .starting, .running: false
        }
    }

    public var canStop: Bool {
        switch status {
        case .starting, .running: true
        case .stopped, .failed: false
        }
    }
}
