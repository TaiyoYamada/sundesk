//
//  UserDefaultsSettingsRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

/// 設定を UserDefaults に保存する。
///
/// 起動引数でも上書きできる（例: UI テストの `-engine.startsAutomatically NO`）。
/// 起動引数の値は文字列で届くので、真偽値は `bool(forKey:)` で読む。
public struct UserDefaultsSettingsRepository: SettingsRepository, @unchecked Sendable {
    public enum Key {
        public static let vaultDirectory = "vault.directory"
        public static let engineDirectory = "engine.directory"
        public static let uvExecutable = "engine.uvExecutable"
        public static let startsEngineAutomatically = "engine.startsAutomatically"
    }

    // UserDefaults はスレッドをまたいで使ってよい（Apple のドキュメントで保証されている）
    private let userDefaults: UserDefaults
    public let defaults: SettingsDefaults

    public init(userDefaults: UserDefaults = .standard, defaults: SettingsDefaults) {
        self.userDefaults = userDefaults
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        AppSettings(
            vaultDirectory: userDefaults.string(forKey: Key.vaultDirectory) ?? "",
            engineDirectory: userDefaults.string(forKey: Key.engineDirectory) ?? "",
            uvExecutable: userDefaults.string(forKey: Key.uvExecutable) ?? "",
            startsEngineAutomatically: userDefaults.object(forKey: Key.startsEngineAutomatically) == nil
                ? true : userDefaults.bool(forKey: Key.startsEngineAutomatically)
        )
    }

    public func save(_ settings: AppSettings) {
        userDefaults.set(settings.vaultDirectory, forKey: Key.vaultDirectory)
        userDefaults.set(settings.engineDirectory, forKey: Key.engineDirectory)
        userDefaults.set(settings.uvExecutable, forKey: Key.uvExecutable)
        userDefaults.set(settings.startsEngineAutomatically, forKey: Key.startsEngineAutomatically)
    }
}
