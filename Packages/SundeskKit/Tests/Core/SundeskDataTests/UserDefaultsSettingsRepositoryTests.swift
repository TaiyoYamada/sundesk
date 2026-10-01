//
//  UserDefaultsSettingsRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import Testing

@Suite("UserDefaultsSettingsRepository")
struct UserDefaultsSettingsRepositoryTests {
    private let defaults = SettingsDefaults(vaultDirectory: "/v", engineDirectory: "/e", uvExecutable: "/u")

    private func makeRepository(_ name: String) throws -> (UserDefaultsSettingsRepository, UserDefaults) {
        let userDefaults = try #require(UserDefaults(suiteName: name))
        userDefaults.removePersistentDomain(forName: name)
        return (UserDefaultsSettingsRepository(userDefaults: userDefaults, defaults: defaults), userDefaults)
    }

    @Test("何も保存していなければ、空欄と自動起動あり")
    func emptyByDefault() throws {
        let (repository, _) = try makeRepository(#function)
        #expect(repository.load() == AppSettings())
    }

    @Test("保存したものを読める")
    func roundTrip() throws {
        let (repository, _) = try makeRepository(#function)
        let settings = AppSettings(
            vaultDirectory: "/a", engineDirectory: "/b", uvExecutable: "/c", startsEngineAutomatically: false)

        repository.save(settings)

        #expect(repository.load() == settings)
    }

    @Test("起動引数のように文字列で NO が入っていても、自動起動しないと読む", arguments: ["NO", "false", "0"])
    func readsStringBooleans(value: String) throws {
        let (repository, userDefaults) = try makeRepository("\(#function).\(value)")
        userDefaults.set(value, forKey: UserDefaultsSettingsRepository.Key.startsEngineAutomatically)

        #expect(!repository.load().startsEngineAutomatically)
    }
}
