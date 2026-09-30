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
    /// 整理（フォルダを作る、移すなど）に失敗したときのメッセージ。
    public var operationMessage: String?
    public private(set) var isSyncing = false
    public var filterText = ""
    private var tree: VaultNode?

    @ObservationIgnored private let syncVault: any SyncVaultUseCase
    @ObservationIgnored private let observeChanges: any ObserveVaultChangesUseCase
    @ObservationIgnored private let locateFile: any LocateFileUseCase
    @ObservationIgnored private let manageFiles: (any ManageFilesUseCase)?
    @ObservationIgnored private var isObserving = false

    public init(
        syncVault: any SyncVaultUseCase,
        observeChanges: any ObserveVaultChangesUseCase,
        locateFile: any LocateFileUseCase,
        manageFiles: (any ManageFilesUseCase)? = nil
    ) {
        self.syncVault = syncVault
        self.observeChanges = observeChanges
        self.locateFile = locateFile
        self.manageFiles = manageFiles
    }

    /// 絞り込みを反映した木（ルートの子の一覧）。
    public var items: [NavigatorItem] {
        (tree?.filtered(by: filterText)?.children ?? []).map(NavigatorItem.init)
    }

    public var vaultName: String {
        tree?.name ?? "Vault"
    }

    /// パスの項目（フォルダも含む。絞り込みは反映しない）。
    public func item(at path: String) -> NavigatorItem? {
        tree?.node(at: path).map(NavigatorItem.init)
    }

    /// 絞り込みを反映した、パスの項目。
    public func filteredItem(at path: String) -> NavigatorItem? {
        tree?.filtered(by: filterText)?.node(at: path).map(NavigatorItem.init)
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

    // MARK: - 整理

    /// 書き換えられるか（読むだけでつないだフォルダの中ではないか）。
    public func canEdit(_ path: String) -> Bool {
        guard let manageFiles else { return false }
        return !manageFiles.isReadOnly(path)
    }

    /// フォルダを作る。作ったパスを返す。
    @discardableResult
    public func createFolder(named name: String, in folder: String) async -> String? {
        await perform { try await $0.createFolder(named: name, in: folder) }
    }

    public func move(_ paths: [String], into folder: String) async {
        _ = await perform { try await $0.move(paths, into: folder) }
    }

    public func rename(_ path: String, to name: String) async {
        _ = await perform { try await $0.rename(path, to: name) }
    }

    public func moveToTrash(_ paths: [String]) async {
        _ = await perform { try await $0.moveToTrash(paths) }
    }

    /// そのフォルダの中の、移し先にできるフォルダ（深さ順）。
    public func folders(under root: String) -> [String] {
        guard let node = tree?.node(at: root) else { return [] }
        var result: [String] = [root]
        func visit(_ node: VaultNode) {
            for child in node.children ?? [] where child.isFolder {
                result.append(child.path)
                visit(child)
            }
        }
        visit(node)
        return result
    }

    private func perform<T>(_ body: (any ManageFilesUseCase) async throws -> T) async -> T? {
        guard let manageFiles else { return nil }
        do {
            let result = try await body(manageFiles)
            operationMessage = nil
            await reload()
            return result
        } catch let error as VaultError {
            operationMessage = error.message
        } catch {
            operationMessage = error.localizedDescription
        }
        return nil
    }
}
