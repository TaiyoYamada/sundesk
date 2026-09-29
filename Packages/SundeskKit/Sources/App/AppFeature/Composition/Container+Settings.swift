//
//  Container+Settings.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import FactoryKit
import Foundation
import SettingsFeature
import SundeskData
import SundeskDomain
import SundeskEngineClient

extension Container {
    // MARK: - Data

    var settingsRepository: Factory<any SettingsRepository> {
        self {
            UserDefaultsSettingsRepository(
                defaults: SettingsDefaults(
                    vaultDirectory: AppPaths.library.path,
                    engineDirectory: EngineLocator.defaultEngineDirectory().path,
                    uvExecutable: EngineLocator.findUV()?.path ?? "/opt/homebrew/bin/uv"
                )
            )
        }
        .singleton
    }

    /// 空欄を既定値で埋めた、今の設定。
    var resolvedSettings: Factory<AppSettings> {
        self {
            let repository = self.settingsRepository()
            return repository.load().resolved(with: repository.defaults)
        }
    }

    // MARK: - UseCase

    var loadSettings: Factory<any LoadSettingsUseCase> {
        self { LoadSettingsInteractor(repository: self.settingsRepository()) }
    }

    var updateSettings: Factory<any UpdateSettingsUseCase> {
        self { UpdateSettingsInteractor(repository: self.settingsRepository()) }
    }

    // MARK: - ViewModel

    @MainActor
    var vaultSettingsViewModel: Factory<VaultSettingsViewModel> {
        self {
            VaultSettingsViewModel(
                loadSettings: self.loadSettings(), updateSettings: self.updateSettings(),
                library: self.manageLibrary(), samplePath: AppPaths.sampleLibrary.path)
        }
    }

    @MainActor
    var engineSettingsViewModel: Factory<EngineSettingsViewModel> {
        self { EngineSettingsViewModel(loadSettings: self.loadSettings(), updateSettings: self.updateSettings()) }
    }
}
