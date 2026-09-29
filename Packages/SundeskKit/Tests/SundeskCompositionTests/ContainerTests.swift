//
//  ContainerTests.swift
//  SundeskCompositionTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryTesting
import Foundation
import SundeskDomain
import SundeskEngine
import SundeskPresentation
import Testing

@testable import SundeskComposition

@MainActor
@Suite("Composition Root", .container)
struct ContainerTests {
    @Test("エンジンの状態の ViewModel はウインドウ間で共有する")
    func engineStatusViewModelIsShared() {
        let first = Container.shared.engineStatusViewModel()
        let second = Container.shared.engineStatusViewModel()

        #expect(first === second)
    }

    @Test("Repository は 1 つのエンジンを共有する")
    func engineRepositoryIsSingleton() async {
        let first = Container.shared.engineProcess()
        let second = Container.shared.engineProcess()

        #expect(first === second)
    }

    @Test("UseCase を差し替えると、ViewModel はそれを使う")
    func viewModelUsesRegisteredUseCase() async {
        Container.shared.startEngine.register {
            FailingStartEngine(failure: EngineFailure(message: "差し替えた"))
        }

        let viewModel = Container.shared.engineStatusViewModel()
        await viewModel.start()

        #expect(viewModel.lastError == "差し替えた")
    }
}

private struct FailingStartEngine: StartEngineUseCase {
    let failure: EngineFailure
    func callAsFunction() async throws(EngineFailure) { throw failure }
}

@Suite("EngineSettings")
struct EngineSettingsTests {
    @Test("自動起動は、値がなければ有効")
    func startsAutomaticallyByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)

        #expect(EngineSettings.startsAutomatically(defaults: defaults))
    }

    @Test("起動引数のように文字列で NO が入っていても、無効と読む", arguments: ["NO", "false", "0"])
    func readsStringValues(value: String) throws {
        let suite = "\(#function).\(value)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(value, forKey: EngineSettings.Key.startsAutomatically)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!EngineSettings.startsAutomatically(defaults: defaults))
    }

    @Test("場所が空欄なら既定値を使い、指定があればそれを使う")
    func configurationFallsBackToDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        defaults.set("", forKey: EngineSettings.Key.engineDirectory)
        #expect(
            EngineSettings.configuration(defaults: defaults).engineDirectory.path
                == EngineSettings.defaultEngineDirectory)

        defaults.set("/custom/engine", forKey: EngineSettings.Key.engineDirectory)
        #expect(EngineSettings.configuration(defaults: defaults).engineDirectory.path == "/custom/engine")
    }
}
