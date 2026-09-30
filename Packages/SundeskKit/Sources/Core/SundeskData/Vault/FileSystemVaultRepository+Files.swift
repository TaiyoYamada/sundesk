//
//  FileSystemVaultRepository+Files.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// ファイルとフォルダの整理（作る、移す、名前を変える、ゴミ箱に入れる、取り込む）。つないだフォルダの中は変えない。
extension FileSystemVaultRepository {
    @concurrent
    public func createFolder(named name: String, in folder: String) async throws(VaultError) -> String {
        let parent = try writableURL(folder)
        let target = Self.unique(name, in: parent)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            throw .unwritable(path: folder, reason: error.localizedDescription)
        }
        return Self.join(folder, target.lastPathComponent)
    }

    @concurrent
    public func move(_ path: String, into folder: String) async throws(VaultError) -> String {
        let source = try writableURL(path)
        let parent = try writableURL(folder)
        let target = Self.unique(source.lastPathComponent, in: parent)
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
        return Self.join(folder, target.lastPathComponent)
    }

    @concurrent
    public func rename(_ path: String, to name: String) async throws(VaultError) -> String {
        let source = try writableURL(path)
        let parent = source.deletingLastPathComponent()
        let target = parent.appending(path: name)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw .unwritable(path: path, reason: "同じ名前のものがあります（\(name)）")
        }
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
        return Self.join((path as NSString).deletingLastPathComponent, name)
    }

    @concurrent
    public func moveToTrash(_ path: String) async throws(VaultError) {
        let url = try writableURL(path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
    }

    @concurrent
    public func importFiles(_ urls: [URL], into folder: String) async throws(VaultError) -> [String] {
        let parent = try writableURL(folder)
        var imported: [String] = []
        for url in urls {
            let target = Self.unique(url.lastPathComponent, in: parent)
            do {
                try FileManager.default.copyItem(at: url, to: target)
            } catch {
                throw .unwritable(path: folder, reason: error.localizedDescription)
            }
            imported.append(Self.join(folder, target.lastPathComponent))
        }
        return imported
    }

    // MARK: - 内部

    /// 書き換えてよい、ライブラリの中の場所（空のパスはライブラリのルート）。
    private func writableURL(_ path: String) throws(VaultError) -> URL {
        guard !isReadOnly(path) else { throw .readOnly(path: path) }
        let root = rootURL().standardizedFileURL
        let url = (path.isEmpty ? root : root.appending(path: path)).standardizedFileURL
        guard url == root || url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path)
        else { throw .fileNotFound(path: path) }
        return url
    }

    /// 名前が重なれば「名前 2」のように番号を付ける。
    static func unique(_ name: String, in folder: URL) -> URL {
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var candidate = folder.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : "\(folder)/\(name)"
    }
}
