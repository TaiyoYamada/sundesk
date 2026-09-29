//
//  FileNavigatorViewModel.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// ナビゲータの「ファイル」。Vault の木を持ち、変更を見張って索引を最新に保つ。
@MainActor
@Observable
public final class FileNavigatorViewModel {
    public private(set) var tree: VaultNode?
    public private(set) var errorMessage: String?
    public private(set) var isIndexing = false
    public var filterText = ""

    @ObservationIgnored private let loadTree: any LoadVaultTreeUseCase
    @ObservationIgnored private let observeChanges: any ObserveVaultChangesUseCase
    @ObservationIgnored private let indexVault: any IndexVaultUseCase
    @ObservationIgnored private var isObserving = false

    public init(
        loadTree: any LoadVaultTreeUseCase,
        observeChanges: any ObserveVaultChangesUseCase,
        indexVault: any IndexVaultUseCase
    ) {
        self.loadTree = loadTree
        self.observeChanges = observeChanges
        self.indexVault = indexVault
    }

    /// 絞り込みを反映した木（ルートの子の一覧）。
    public var visibleNodes: [VaultNode] {
        tree?.filtered(by: filterText)?.children ?? []
    }

    public var vaultName: String {
        tree?.name ?? "Vault"
    }

    /// 木を読み、索引を更新する。
    public func reload() async {
        do {
            let loaded = try await loadTree()
            if loaded != tree { tree = loaded }
            errorMessage = nil
        } catch {
            tree = nil
            errorMessage = DocumentViewModel.message(for: error)
            return
        }
        isIndexing = true
        _ = try? await indexVault()
        isIndexing = false
    }

    /// Vault の変更を見張り、そのたびに読み直す。複数のウインドウから呼ばれても 1 回だけ見張る。
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
