//
//  ManageFilesUseCase.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// ライブラリのファイルとフォルダを整理する（フォルダでくくる、移す、名前を変える、消す）。
///
/// 読むだけでつないだフォルダ（~/Research、study-artifact）の中は変えない。
public protocol ManageFilesUseCase: Sendable {
    func isReadOnly(_ path: String) -> Bool
    func createFolder(named name: String, in folder: String) async throws(VaultError) -> String
    func move(_ paths: [String], into folder: String) async throws(VaultError) -> [String]
    func rename(_ path: String, to name: String) async throws(VaultError) -> String
    func moveToTrash(_ paths: [String]) async throws(VaultError)
}

public struct ManageFilesInteractor: ManageFilesUseCase {
    private let vault: any VaultRepository

    public init(vault: any VaultRepository) {
        self.vault = vault
    }

    public func isReadOnly(_ path: String) -> Bool {
        vault.isReadOnly(path)
    }

    public func createFolder(named name: String, in folder: String) async throws(VaultError) -> String {
        guard !vault.isReadOnly(folder) else { throw .readOnly(path: folder) }
        return try await vault.createFolder(named: Self.cleanName(name, fallback: "新しいフォルダ"), in: folder)
    }

    public func move(_ paths: [String], into folder: String) async throws(VaultError) -> [String] {
        guard !vault.isReadOnly(folder) else { throw .readOnly(path: folder) }
        var moved: [String] = []
        for path in paths {
            guard !vault.isReadOnly(path) else { throw .readOnly(path: path) }
            // 自分の中や、今いるフォルダへは移さない
            let parent = (path as NSString).deletingLastPathComponent
            guard folder != path, !folder.hasPrefix(path + "/"), parent != folder else { continue }
            moved.append(try await vault.move(path, into: folder))
        }
        return moved
    }

    public func rename(_ path: String, to name: String) async throws(VaultError) -> String {
        guard !vault.isReadOnly(path) else { throw .readOnly(path: path) }
        let current = (path as NSString).lastPathComponent
        let cleaned = Self.cleanName(name, fallback: current)
        guard cleaned != current else { return path }
        return try await vault.rename(path, to: cleaned)
    }

    public func moveToTrash(_ paths: [String]) async throws(VaultError) {
        for path in paths {
            guard !vault.isReadOnly(path) else { throw .readOnly(path: path) }
            try await vault.moveToTrash(path)
        }
    }

    /// ファイル名に使えない文字（`/` と `:`）を除き、前後の空白を落とす。
    static func cleanName(_ name: String, fallback: String) -> String {
        let cleaned = name.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? fallback : cleaned
    }
}
