//
//  Container+Engine.swift
//  SundeskComposition
//
//  Created by 山田大陽 on 2026/09/29.
//

@_exported import FactoryKit
import SundeskData
import SundeskDomain
import SundeskEngine
import SundeskPresentation

// Composition Root。すべてのモジュールを知っているのはここだけで、
// 各層はコンストラクタで依存を受け取る。Factory はここでの組み立てにだけ使う。

extension Container {
    // MARK: - Infrastructure

    var engineProcess: Factory<EngineProcess> {
        self { EngineProcess(configuration: { EngineSettings.configuration() }) }
            .singleton
    }

    // MARK: - Data

    var engineRepository: Factory<any EngineRepository> {
        self { EngineRepositoryImpl(process: self.engineProcess()) }
            .singleton
    }

    // MARK: - UseCase

    public var startEngine: Factory<any StartEngineUseCase> {
        self { StartEngineInteractor(repository: self.engineRepository()) }
    }

    public var stopEngine: Factory<any StopEngineUseCase> {
        self { StopEngineInteractor(repository: self.engineRepository()) }
    }

    public var observeEngineStatus: Factory<any ObserveEngineStatusUseCase> {
        self { ObserveEngineStatusInteractor(repository: self.engineRepository()) }
    }

    // MARK: - ViewModel

    /// エンジンは 1 つなので、状態の ViewModel もウインドウ間で共有する。
    @MainActor
    public var engineStatusViewModel: Factory<EngineStatusViewModel> {
        self {
            EngineStatusViewModel(
                startEngine: self.startEngine(),
                stopEngine: self.stopEngine(),
                observeStatus: self.observeEngineStatus()
            )
        }
        .singleton
    }
}
