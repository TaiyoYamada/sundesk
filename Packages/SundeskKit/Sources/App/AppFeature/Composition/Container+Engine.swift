//
//  Container+Engine.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import FactoryKit
import Foundation
import SundeskData
import SundeskDomain
import SundeskEngineClient

// Composition Root。すべてのモジュールを知っているのはここだけで、
// 各層はコンストラクタで依存を受け取る。Factory はここでの組み立てにだけ使う（ADR 0004）。

extension Container {
    // MARK: - Infrastructure

    var engineProcess: Factory<EngineProcess> {
        self {
            let settings = self.settingsRepository()
            return EngineProcess(configuration: {
                let resolved = settings.load().resolved(with: settings.defaults)
                return EngineConfiguration(
                    engineDirectory: URL(filePath: resolved.engineDirectory, directoryHint: .isDirectory),
                    uvExecutable: URL(filePath: resolved.uvExecutable)
                )
            })
        }
        .singleton
    }

    // MARK: - Data

    var engineRepository: Factory<any EngineRepository> {
        self { EngineRepositoryImpl(process: self.engineProcess()) }
            .singleton
    }

    // MARK: - UseCase

    var startEngine: Factory<any StartEngineUseCase> {
        self { StartEngineInteractor(repository: self.engineRepository()) }
    }

    var stopEngine: Factory<any StopEngineUseCase> {
        self { StopEngineInteractor(repository: self.engineRepository()) }
    }

    var observeEngineStatus: Factory<any ObserveEngineStatusUseCase> {
        self { ObserveEngineStatusInteractor(repository: self.engineRepository()) }
    }

    // MARK: - ViewModel

    /// エンジンは 1 つなので、状態の ViewModel もウインドウ間で共有する。
    @MainActor
    var engineStatusViewModel: Factory<EngineStatusViewModel> {
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
