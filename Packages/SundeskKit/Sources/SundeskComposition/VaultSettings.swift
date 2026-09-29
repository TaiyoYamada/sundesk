//
//  VaultSettings.swift
//  SundeskComposition
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 設定画面で変えられる Vault の場所。UserDefaults に保存する。
public enum VaultSettings {
    public enum Key {
        public static let directory = "vault.directory"
    }

    /// 既定の Vault。リポジトリに入っているモックの `SampleVault/`。
    public static func defaultDirectory(sourceFile: String = #filePath) -> URL {
        // .../sundesk/Packages/SundeskKit/Sources/SundeskComposition/VaultSettings.swift
        URL(filePath: sourceFile)
            .deletingLastPathComponent()  // SundeskComposition
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // SundeskKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // sundesk（リポジトリのルート）
            .appending(path: "SampleVault", directoryHint: .isDirectory)
    }

    public static func directory(defaults: UserDefaults = .standard) -> URL {
        guard let path = defaults.string(forKey: Key.directory), !path.isEmpty else { return defaultDirectory() }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
