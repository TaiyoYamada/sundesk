//
//  Container+Library.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import FactoryKit
import Foundation
import LibraryFeature
import SundeskData
import SundeskDomain

extension Container {
    // MARK: - Data

    /// アプリのデータフォルダ（library.store と Storage/ を置く）。
    /// UI テストは起動引数（`-library.directory <パス>`）で、一時フォルダに差し替える。
    var dataDirectory: Factory<URL> {
        self {
            if let path = UserDefaults.standard.string(forKey: "library.directory") {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
            do {
                return try AppDataDirectory.url("Library")
            } catch {
                fatalError("データフォルダを作れませんでした: \(error)")
            }
        }
        .singleton
    }

    var referenceRepository: Factory<any ReferenceRepository> {
        self {
            let url = self.dataDirectory().appending(path: "library.store")
            do {
                return try SwiftDataReferenceRepository.open(at: url)
            } catch {
                fatalError("ライブラリ（\(url.path)）を開けませんでした: \(error)")
            }
        }
        .singleton
    }

    var attachmentStore: Factory<any AttachmentStore> {
        self { FileAttachmentStore(root: self.dataDirectory().appending(path: "Storage", directoryHint: .isDirectory)) }
    }

    var bibliography: Factory<any BibliographyService> {
        self { OnlineBibliography() }
    }

    var pdfReader: Factory<any PDFReading> {
        self { PDFKitReader() }
    }

    var paperSummarizer: Factory<any PaperSummarizer> {
        self { FoundationModelsSummarizer() }
    }

    // MARK: - UseCase

    var manageLibrary: Factory<any ManageLibraryUseCase> {
        self {
            LibraryInteractor(
                repository: self.referenceRepository(), attachments: self.attachmentStore(),
                bibliography: self.bibliography(), pdfs: self.pdfReader())
        }
    }

    var summarizePaper: Factory<any SummarizePaperUseCase> {
        self {
            SummarizePaperInteractor(
                summarizer: self.paperSummarizer(), repository: self.referenceRepository(),
                attachments: self.attachmentStore(), pdfs: self.pdfReader())
        }
    }

    // MARK: - 画面

    @MainActor
    var libraryDependencies: Factory<LibraryDependencies> {
        self { LibraryDependencies(library: self.manageLibrary(), summarize: self.summarizePaper()) }
    }
}
