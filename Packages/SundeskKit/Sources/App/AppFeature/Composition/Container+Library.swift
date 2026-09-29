//
//  Container+Library.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import Foundation
import LibraryFeature
import SundeskData
import SundeskDomain

extension Container {
    // MARK: - Data

    /// 研究ライブラリ（Vault と同じフォルダ）。
    var libraryRepository: Factory<any LibraryRepository> {
        self {
            let settings = self.settingsRepository()
            return FileSystemLibraryRepository(
                root: {
                    URL(
                        filePath: settings.load().resolved(with: settings.defaults).vaultDirectory,
                        directoryHint: .isDirectory)
                },
                markdown: self.markdownParser())
        }
        .singleton
    }

    var bibliography: Factory<any BibliographyService> {
        self { OnlineBibliography() }
    }

    var pdfInspector: Factory<any PDFInspecting> {
        self { PDFKitInspector() }
    }

    // MARK: - UseCase

    var manageLibrary: Factory<any ManageLibraryUseCase> {
        self {
            LibraryInteractor(
                repository: self.libraryRepository(), bibliography: self.bibliography(), pdfs: self.pdfInspector())
        }
    }

    // MARK: - ViewModel

    @MainActor
    var libraryViewModel: Factory<LibraryViewModel> {
        self { LibraryViewModel(library: self.manageLibrary(), observeChanges: self.observeVaultChanges()) }
    }
}
