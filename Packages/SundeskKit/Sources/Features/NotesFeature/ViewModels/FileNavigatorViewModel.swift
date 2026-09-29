//
//  FileNavigatorViewModel.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// ナビゲータの「ファイル」。Vault の木を持ち、変更を見張って同期する。
@MainActor
@Observable
public final class FileNavigatorViewModel {
    public private(set) var errorMessage: String?
    public private(set) var isSyncing = false
    public var filterText = ""
    private var tree: VaultNode?

    @ObservationIgnored private let syncVault: any SyncVaultUseCase
    @ObservationIgnored private let observeChanges: any ObserveVaultChangesUseCase
    @ObservationIgnored private let locateFile: any LocateFileUseCase
    @ObservationIgnored private var isObserving = false

    public init(
        syncVault: any SyncVaultUseCase,
        observeChanges: any ObserveVaultChangesUseCase,
        locateFile: any LocateFileUseCase
    ) {
        self.syncVault = syncVault
        self.observeChanges = observeChanges
        self.locateFile = locateFile
    }

    /// 絞り込みを反映した木（ルートの子の一覧）。
    public var items: [NavigatorItem] {
        (tree?.filtered(by: filterText)?.children ?? []).map(NavigatorItem.init)
    }

    public var vaultName: String {
        tree?.name ?? "Vault"
    }

    /// パスがファイル（フォルダではない）か。
    public func isFile(_ path: String) -> Bool {
        tree?.node(at: path).map { !$0.isFolder } ?? false
    }

    /// Finder で表示するための、ファイルの場所。
    public func fileURL(for path: String) -> URL {
        locateFile(path)
    }

    /// 木を読み、索引を更新する。
    public func reload() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let loaded = try await syncVault()
            if loaded != tree { tree = loaded }
            errorMessage = nil
        } catch {
            tree = nil
            errorMessage = error.message
        }
    }

    /// Vault の変更を見張り、そのたびに同期する。複数のウインドウから呼ばれても 1 回だけ見張る。
    public func observe() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        await reload()
        for await _ in observeChanges() {
            await reload()
        }
    }
}
