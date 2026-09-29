//
//  Container+Vault.swift
//  SundeskComposition
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import Foundation
import OSLog
import SundeskData
import SundeskDomain
import SundeskPresentation
import SwiftData

extension Container {
    // MARK: - Data

    var vaultRepository: Factory<any VaultRepository> {
        self { FileSystemVaultRepository(root: { VaultSettings.directory() }) }
            .singleton
    }

    /// 索引の保存先。Vault ごとに別のファイルにする。開けなければメモリ上に作る。
    var noteIndexModelContainer: Factory<ModelContainer> {
        self {
            do {
                return try NoteIndexStore.makeContainer(
                    url: NoteIndexStore.defaultURL(forVault: VaultSettings.directory()))
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

    public var loadVaultTree: Factory<any LoadVaultTreeUseCase> {
        self { LoadVaultTreeInteractor(vault: self.vaultRepository()) }
    }

    public var observeVaultChanges: Factory<any ObserveVaultChangesUseCase> {
        self { ObserveVaultChangesInteractor(vault: self.vaultRepository()) }
    }

    public var openDocument: Factory<any OpenDocumentUseCase> {
        self { OpenDocumentInteractor(vault: self.vaultRepository()) }
    }

    public var resolveLink: Factory<any ResolveLinkUseCase> {
        self { ResolveLinkInteractor(vault: self.vaultRepository()) }
    }

    public var indexVault: Factory<any IndexVaultUseCase> {
        self { IndexVaultInteractor(vault: self.vaultRepository(), index: self.noteIndexRepository()) }
    }

    public var findBacklinks: Factory<any FindBacklinksUseCase> {
        self { FindBacklinksInteractor(index: self.noteIndexRepository()) }
    }

    public var searchNotes: Factory<any SearchNotesUseCase> {
        self { SearchNotesInteractor(index: self.noteIndexRepository()) }
    }

    public var listTags: Factory<any ListTagsUseCase> {
        self { ListTagsInteractor(index: self.noteIndexRepository()) }
    }

    public var findNotesByTag: Factory<any FindNotesByTagUseCase> {
        self { FindNotesByTagInteractor(index: self.noteIndexRepository()) }
    }

    public var observeNoteIndex: Factory<any ObserveNoteIndexUseCase> {
        self { ObserveNoteIndexInteractor(index: self.noteIndexRepository()) }
    }

    // MARK: - ViewModel

    /// Vault は 1 つなので、ファイルの木はウインドウ間で共有する。
    @MainActor
    public var fileNavigatorViewModel: Factory<FileNavigatorViewModel> {
        self {
            FileNavigatorViewModel(
                loadTree: self.loadVaultTree(),
                observeChanges: self.observeVaultChanges(),
                indexVault: self.indexVault()
            )
        }
        .singleton
    }

    /// ウインドウごとに作る（開いているタブはウインドウごとに違う）。
    @MainActor
    public var workspaceViewModel: Factory<WorkspaceViewModel> {
        self {
            WorkspaceViewModel(resolveLink: self.resolveLink()) { path in
                DocumentViewModel(path: path, openDocument: self.openDocument(), findBacklinks: self.findBacklinks())
            }
        }
    }

    @MainActor
    public var searchViewModel: Factory<SearchViewModel> {
        self { SearchViewModel(searchNotes: self.searchNotes()) }
    }

    @MainActor
    public var tagsViewModel: Factory<TagsViewModel> {
        self {
            TagsViewModel(
                listTags: self.listTags(), findNotes: self.findNotesByTag(), observeIndex: self.observeNoteIndex())
        }
    }
}
