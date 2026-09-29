//
//  ContainerTests.swift
//  AppFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import FactoryKit
import FactoryTesting
import Foundation
import NotesFeature
import SundeskData
import SundeskDomain
import Testing
import WorkspaceFeature

@testable import AppFeature

@Suite("Composition Root", .container)
struct ContainerTests {
    @Test("エンジンの状態と、ファイルの木はウインドウ間で共有する")
    func sharedViewModels() {
        #expect(Container.shared.engineStatusViewModel() === Container.shared.engineStatusViewModel())
        #expect(Container.shared.fileNavigatorViewModel() === Container.shared.fileNavigatorViewModel())
        #expect(Container.shared.engineProcess() === Container.shared.engineProcess())
    }

    @Test("ワークスペース（タブ）はウインドウごとに作る")
    func workspacePerWindow() {
        let dependencies = Container.shared.workspaceDependencies()
        #expect(dependencies.makeWorkspace() !== dependencies.makeWorkspace())
    }

    @Test("UseCase を差し替えると、ViewModel はそれを使う")
    func viewModelUsesRegisteredUseCase() async {
        Container.shared.startEngine.register { FailingStartEngine(failure: EngineFailure(message: "差し替えた")) }

        let viewModel = Container.shared.engineStatusViewModel()
        await viewModel.start()

        #expect(viewModel.lastError == "差し替えた")
    }

    @Test("既定の Vault はリポジトリの SampleVault で、中身を開ける")
    func opensSampleVault() async throws {
        #expect(AppPaths.sampleVault.lastPathComponent == "SampleVault")
        let inMemory = try NoteIndexStore.makeContainer(url: nil)
        Container.shared.noteIndexModelContainer.register { inMemory }
        Container.shared.settingsRepository.register {
            UserDefaultsSettingsRepository(
                userDefaults: UserDefaults(suiteName: "AppFeatureTests")!,
                defaults: SettingsDefaults(
                    vaultDirectory: AppPaths.sampleVault.path, engineDirectory: "", uvExecutable: "")
            )
        }

        let openDocument = Container.shared.openDocument()
        let document = try await openDocument(path: "ホーム.md")

        #expect(document.title == "ホーム")
    }
}

private struct FailingStartEngine: StartEngineUseCase {
    let failure: EngineFailure
    func callAsFunction() async throws(EngineFailure) { throw failure }
}
