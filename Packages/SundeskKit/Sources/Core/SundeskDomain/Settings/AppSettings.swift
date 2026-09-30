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
    /// 研究のデータのフォルダ（~/Research）。読むだけでつなぐ。
    public var researchDirectory: String
    /// study-artifact のフォルダ。研究に関係するところだけを読むだけでつなぐ。
    public var studyDirectory: String
    /// study-artifact の中で読むフォルダ。空なら既定（``ResearchSources/defaultStudySections``）。
    public var studySections: [String]

    public init(
        vaultDirectory: String = "", engineDirectory: String = "", uvExecutable: String = "",
        startsEngineAutomatically: Bool = true, researchDirectory: String = "", studyDirectory: String = "",
        studySections: [String] = []
    ) {
        self.vaultDirectory = vaultDirectory
        self.engineDirectory = engineDirectory
        self.uvExecutable = uvExecutable
        self.startsEngineAutomatically = startsEngineAutomatically
        self.researchDirectory = researchDirectory
        self.studyDirectory = studyDirectory
        self.studySections = studySections
    }
}

/// 設定が空欄のときに使う既定値。
public struct SettingsDefaults: Equatable, Sendable {
    public let vaultDirectory: String
    public let engineDirectory: String
    public let uvExecutable: String
    public let researchDirectory: String
    public let studyDirectory: String

    public init(
        vaultDirectory: String, engineDirectory: String, uvExecutable: String, researchDirectory: String = "",
        studyDirectory: String = ""
    ) {
        self.vaultDirectory = vaultDirectory
        self.engineDirectory = engineDirectory
        self.uvExecutable = uvExecutable
        self.researchDirectory = researchDirectory
        self.studyDirectory = studyDirectory
    }
}

extension AppSettings {
    /// 空欄を既定値で埋めた値。
    public func resolved(with defaults: SettingsDefaults) -> AppSettings {
        AppSettings(
            vaultDirectory: vaultDirectory.isEmpty ? defaults.vaultDirectory : vaultDirectory,
            engineDirectory: engineDirectory.isEmpty ? defaults.engineDirectory : engineDirectory,
            uvExecutable: uvExecutable.isEmpty ? defaults.uvExecutable : uvExecutable,
            startsEngineAutomatically: startsEngineAutomatically,
            researchDirectory: researchDirectory.isEmpty ? defaults.researchDirectory : researchDirectory,
            studyDirectory: studyDirectory.isEmpty ? defaults.studyDirectory : studyDirectory,
            studySections: studySections
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

/// study-artifact の中のフォルダを調べる（どこを読むかを選ぶため）。
public protocol ListStudySectionsUseCase: Sendable {
    /// ノートのフォルダの中のフォルダ名（名前順）。
    func callAsFunction(in studyDirectory: String) -> [String]
}
