//
//  Container+Lab.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import Foundation
import ImagesFeature
import LabFeature
import OSLog
import SundeskData
import SundeskDomain
import SwiftData

extension Container {
    // MARK: - Data

    /// 実験室の記録の保存先（アプリ全体で 1 つ）。開けなければメモリ上に作る。
    var labModelContainer: Factory<ModelContainer> {
        self {
            do {
                return try LabStore.makeContainer(url: LabStore.defaultURL())
            } catch {
                Logger(subsystem: "com.taiyou.sundesk", category: "lab")
                    .error("実験室の記録を開けないので、メモリ上に作る: \(error.localizedDescription, privacy: .public)")
                // メモリ上の SwiftData は、スキーマが正しい限り失敗しない
                // swiftlint:disable:next force_try
                return try! LabStore.makeContainer(url: nil)
            }
        }
        .singleton
    }

    var labRecords: Factory<any LabRecordRepository> {
        self { SwiftDataLabRecordRepository(modelContainer: self.labModelContainer()) }
            .singleton
    }

    var labGateway: Factory<EngineLabGateway> {
        self { EngineLabGateway(process: self.engineProcess()) }
    }

    var labFiles: Factory<any LabFileLocations> {
        self { AppDataLabFiles() }
    }

    // MARK: - UseCase

    var labUseCases: Factory<any LabUseCases> {
        self {
            LabInteractor(
                engine: self.labGateway(), records: self.labRecords(), vault: self.vaultRepository(),
                markdown: self.markdownParser(), files: self.labFiles())
        }
    }

    var modelManagement: Factory<any ModelManagementUseCase> {
        self { ModelManagementInteractor(repository: self.labGateway()) }
    }

    var imageGeneration: Factory<any ImageGenerationUseCase> {
        self {
            ImageGenerationInteractor(engine: self.labGateway(), records: self.labRecords(), files: self.labFiles())
        }
    }

    var loadVaultTree: Factory<any LoadVaultTreeUseCase> {
        self { LoadVaultTreeInteractor(vault: self.vaultRepository()) }
    }

    // MARK: - ViewModel

    @MainActor
    var labViewModel: Factory<LabViewModel> {
        self {
            LabViewModel(
                lab: self.labUseCases(), modelManagement: self.modelManagement(), loadVaultTree: self.loadVaultTree())
        }
    }

    @MainActor
    var modelsViewModel: Factory<ModelsViewModel> {
        self { ModelsViewModel(management: self.modelManagement()) }
    }

    @MainActor
    var imagesViewModel: Factory<ImagesViewModel> {
        self { ImagesViewModel(generation: self.imageGeneration()) }
    }
}
