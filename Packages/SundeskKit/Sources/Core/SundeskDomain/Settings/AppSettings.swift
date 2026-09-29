//
//  AppSettings.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 設定画面で変えられる設定。空文字は「既定値を使う」を表す。
public struct AppSettings: Equatable, Sendable {
    /// Vault のフォルダ。
    public var vaultDirectory: String
    /// Python エンジンのフォルダ（pyproject.toml のあるところ）。
    public var engineDirectory: String
    /// uv の実行ファイル。
    public var uvExecutable: String
    public var startsEngineAutomatically: Bool

    public init(
        vaultDirectory: String = "", engineDirectory: String = "", uvExecutable: String = "",
        startsEngineAutomatically: Bool = true
    ) {
        self.vaultDirectory = vaultDirectory
        self.engineDirectory = engineDirectory
        self.uvExecutable = uvExecutable
        self.startsEngineAutomatically = startsEngineAutomatically
    }
}

/// 設定が空欄のときに使う既定値。
public struct SettingsDefaults: Equatable, Sendable {
    public let vaultDirectory: String
    public let engineDirectory: String
    public let uvExecutable: String

    public init(vaultDirectory: String, engineDirectory: String, uvExecutable: String) {
        self.vaultDirectory = vaultDirectory
        self.engineDirectory = engineDirectory
        self.uvExecutable = uvExecutable
    }
}

extension AppSettings {
    /// 空欄を既定値で埋めた値。
    public func resolved(with defaults: SettingsDefaults) -> AppSettings {
        AppSettings(
            vaultDirectory: vaultDirectory.isEmpty ? defaults.vaultDirectory : vaultDirectory,
            engineDirectory: engineDirectory.isEmpty ? defaults.engineDirectory : engineDirectory,
            uvExecutable: uvExecutable.isEmpty ? defaults.uvExecutable : uvExecutable,
            startsEngineAutomatically: startsEngineAutomatically
        )
    }
}

public protocol SettingsRepository: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    var defaults: SettingsDefaults { get }
}

// MARK: - UseCase

public protocol LoadSettingsUseCase: Sendable {
    func callAsFunction() -> AppSettings
    var defaults: SettingsDefaults { get }
}

public struct LoadSettingsInteractor: LoadSettingsUseCase {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func callAsFunction() -> AppSettings {
        repository.load()
    }

    public var defaults: SettingsDefaults {
        repository.defaults
    }
}

public protocol UpdateSettingsUseCase: Sendable {
    /// 今の設定を読み、`change` で変えて保存する。変えた項目以外は上書きしない。
    func callAsFunction(_ change: (inout AppSettings) -> Void)
}

public struct UpdateSettingsInteractor: UpdateSettingsUseCase {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func callAsFunction(_ change: (inout AppSettings) -> Void) {
        var settings = repository.load()
        change(&settings)
        repository.save(settings)
    }
}
