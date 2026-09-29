//
//  Container+Vault.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import Foundation
import LibraryFeature
import NotesFeature
import OSLog
import SundeskData
import SundeskDomain
import SundeskMarkdown
import SwiftData
import WorkspaceFeature

extension Container {
    // MARK: - Infrastructure

    var markdownParser: Factory<any MarkdownParsing> {
        self { SwiftMarkdownParser() }
            .singleton
    }

    // MARK: - Data

    var vaultRepository: Factory<any VaultRepository> {
        self {
            let settings = self.settingsRepository()
            return FileSystemVaultRepository(root: {
                URL(
                    filePath: settings.load().resolved(with: settings.defaults).vaultDirectory,
                    directoryHint: .isDirectory)
            })
        }
        .singleton
    }

    /// 索引の保存先。Vault ごとに別のファイルにする。開けなければメモリ上に作る。
    var noteIndexModelContainer: Factory<ModelContainer> {
        self {
            let vault = URL(filePath: self.resolvedSettings().vaultDirectory, directoryHint: .isDirectory)
            do {
                return try NoteIndexStore.makeContainer(url: NoteIndexStore.defaultURL(forVault: vault))
            } catch {
                Logger(subsystem: "com.taiyou.sundesk", category: "index")
                    .error("索引を開けないので、メモリ上に作る: \(error.localizedDescription, privacy: .public)")
                // メモリ上の SwiftData は、スキーマが正しい限り失敗しない
                // swiftlint:disable:next force_try
                return try! NoteIndexStore.makeContainer(url: nil)
            }
        }
        .singleton
    }

    var noteIndexRepository: Factory<any NoteIndexRepository> {
        self { SwiftDataNoteIndex(modelContainer: self.noteIndexModelContainer()) }
            .singleton
    }

    // MARK: - UseCase

    var observeVaultChanges: Factory<any ObserveVaultChangesUseCase> {
        self { ObserveVaultChangesInteractor(vault: self.vaultRepository()) }
    }

    var analyzeNote: Factory<any AnalyzeNoteUseCase> {
        self { AnalyzeNoteInteractor(markdown: self.markdownParser()) }
    }

    var openDocument: Factory<any OpenDocumentUseCase> {
        self { OpenDocumentInteractor(vault: self.vaultRepository(), markdown: self.markdownParser()) }
    }

    var saveDocument: Factory<any SaveDocumentUseCase> {
        self { SaveDocumentInteractor(vault: self.vaultRepository()) }
    }

    var locateFile: Factory<any LocateFileUseCase> {
        self { LocateFileInteractor(vault: self.vaultRepository()) }
    }

    var resolveLink: Factory<any ResolveLinkUseCase> {
        self { ResolveLinkInteractor(vault: self.vaultRepository()) }
    }

    var indexVault: Factory<any IndexVaultUseCase> {
        self {
            IndexVaultInteractor(
                vault: self.vaultRepository(), index: self.noteIndexRepository(), markdown: self.markdownParser())
        }
    }

    var syncVault: Factory<any SyncVaultUseCase> {
        self { SyncVaultInteractor(vault: self.vaultRepository(), indexVault: self.indexVault()) }
    }

    var findBacklinks: Factory<any FindBacklinksUseCase> {
        self { FindBacklinksInteractor(index: self.noteIndexRepository()) }
    }

    var searchNotes: Factory<any SearchNotesUseCase> {
        self { SearchNotesInteractor(index: self.noteIndexRepository()) }
    }

    var listTags: Factory<any ListTagsUseCase> {
        self { ListTagsInteractor(index: self.noteIndexRepository()) }
    }

    var findNotesByTag: Factory<any FindNotesByTagUseCase> {
        self { FindNotesByTagInteractor(index: self.noteIndexRepository()) }
    }

    var observeNoteIndex: Factory<any ObserveNoteIndexUseCase> {
        self { ObserveNoteIndexInteractor(index: self.noteIndexRepository()) }
    }

    // MARK: - ViewModel

    /// Vault は 1 つなので、ファイルの木はウインドウ間で共有する。
    @MainActor
    var fileNavigatorViewModel: Factory<FileNavigatorViewModel> {
        self {
            FileNavigatorViewModel(
                syncVault: self.syncVault(),
                observeChanges: self.observeVaultChanges(),
                locateFile: self.locateFile()
            )
        }
        .singleton
    }

    /// すべてのウインドウで開いているファイル（終了する前に保存する）。
    @MainActor
    var openDocumentRegistry: Factory<OpenDocumentRegistry> {
        self { OpenDocumentRegistry() }
            .singleton
    }

    /// ウインドウごとに作る（開いているタブはウインドウごとに違う）。
    @MainActor
    var workspaceViewModel: Factory<WorkspaceViewModel> {
        self {
            WorkspaceViewModel(resolveLink: self.resolveLink()) { path in
                let document = DocumentViewModel(
                    path: path,
                    openDocument: self.openDocument(),
                    saveDocument: self.saveDocument(),
                    analyzeNote: self.analyzeNote(),
                    findBacklinks: self.findBacklinks(),
                    locateFile: self.locateFile()
                )
                self.openDocumentRegistry().register(document)
                return document
            }
        }
    }

    @MainActor
    var searchViewModel: Factory<SearchViewModel> {
        self { SearchViewModel(searchNotes: self.searchNotes()) }
    }

    @MainActor
    var tagsViewModel: Factory<TagsViewModel> {
        self {
            TagsViewModel(
                listTags: self.listTags(), findNotes: self.findNotesByTag(), observeIndex: self.observeNoteIndex())
        }
    }

    /// ウインドウを作るのに必要なもの一式（WorkspaceFeature に渡す）。
    @MainActor
    var workspaceDependencies: Factory<WorkspaceDependencies> {
        self {
            WorkspaceDependencies(
                fileNavigator: self.fileNavigatorViewModel(),
                engineStatus: self.engineStatusViewModel(),
                makeWorkspace: { self.workspaceViewModel() },
                makeSearch: { self.searchViewModel() },
                makeTags: { self.tagsViewModel() },
                makeGraph: { self.graphViewModel() },
                makeLibrary: { self.libraryViewModel() },
                makePaper: { PaperViewModel(key: $0, library: self.manageLibrary()) },
                makeExperiment: { ExperimentViewModel(key: $0, library: self.manageLibrary()) },
                makeComparison: { ComparisonViewModel(keys: $0, library: self.manageLibrary()) },
                makeChat: { self.chatViewModel() },
                makeLab: { self.labViewModel() },
                makeForge: { self.forgeViewModel() },
                makeScratch: { self.scratchViewModel() },
                makeModels: { self.modelsViewModel() },
                makeImages: { self.imagesViewModel() }
            )
        }
    }
}
