//
//  VaultSettingsViewModel.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 設定画面の「Vault」。入力するたびに保存する。
@MainActor
@Observable
public final class VaultSettingsViewModel {
    public var vaultDirectory: String {
        didSet { updateSettings { $0.vaultDirectory = vaultDirectory } }
    }

    /// 空欄のときに使う Vault（入力欄の薄い文字に出す）。
    public let defaultVaultDirectory: String

    @ObservationIgnored private let updateSettings: any UpdateSettingsUseCase

    public init(loadSettings: any LoadSettingsUseCase, updateSettings: any UpdateSettingsUseCase) {
        vaultDirectory = loadSettings().vaultDirectory
        defaultVaultDirectory = loadSettings.defaults.vaultDirectory
        self.updateSettings = updateSettings
    }

    /// 今の設定での Vault のフォルダ（「Finder で開く」に使う）。
    public var effectiveVaultURL: URL {
        URL(filePath: vaultDirectory.isEmpty ? defaultVaultDirectory : vaultDirectory, directoryHint: .isDirectory)
    }
}
