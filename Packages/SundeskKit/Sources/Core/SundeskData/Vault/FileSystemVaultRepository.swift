//
//  FileSystemVaultRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

/// Mac のフォルダを Vault として読む。
public struct FileSystemVaultRepository: VaultRepository {
    private let root: @Sendable () -> URL

    /// - Parameter root: Vault のフォルダ。呼ぶたびに設定から読む。
    public init(root: @escaping @Sendable () -> URL) {
        self.root = root
    }

    @concurrent
    public func loadTree() async throws(VaultError) -> VaultNode {
        let root = root().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .vaultNotFound(path: root.path)
        }
        return VaultNode(
            id: "", name: root.lastPathComponent, kind: .folder, children: Self.children(of: root, path: ""))
    }

    @concurrent
    public func readText(at path: String) async throws(VaultError) -> String {
        let url = try resolve(path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
        // UTF-8 で読めなければ Shift_JIS を試し、それでもだめなら読める部分だけを出す
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(bytes: data, encoding: .utf8)
            ?? String(localized: "（このファイルは文字として読めません）")
    }

    @concurrent
    public func writeText(_ text: String, to path: String) async throws(VaultError) {
        let root = root().standardizedFileURL
        let url = root.appending(path: path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw .fileNotFound(path: path) }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 書きかけのファイルを残さないよう、一時ファイルに書いてから置き換える
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw .unwritable(path: path, reason: error.localizedDescription)
        }
    }

    public func rootURL() -> URL {
        root()
    }

    public func fileInfo(at path: String) async throws(VaultError) -> FileInfo {
        let url = try resolve(path)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        } catch {
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
        return FileInfo(
            path: path,
            size: values.fileSize ?? 0,
            created: values.creationDate,
            modified: values.contentModificationDate ?? .distantPast
        )
    }

    public func fileURL(for path: String) -> URL {
        root().appending(path: path)
    }

    public func changes() -> AsyncStream<Void> {
        let url = root()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watcher = DirectoryWatcher(url: url) { continuation.yield() }
            continuation.onTermination = { _ in withExtendedLifetime(watcher) {} }
        }
    }

    // MARK: - 内部

    /// Vault の中のパスをファイルの場所に直す。Vault の外や、存在しないファイルは拒否する。
    private func resolve(_ path: String) throws(VaultError) -> URL {
        let root = root().standardizedFileURL
        let url = root.appending(path: path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
            throw .fileNotFound(path: path)
        }
        return url
    }

    private static let ignoredNames: Set<String> = ["node_modules", ".build", "DerivedData", "__pycache__"]

    private static func children(of directory: URL, path: String) -> [VaultNode] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )) ?? []

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard !ignoredNames.contains(name) else { return nil }
            let childPath = path.isEmpty ? name : "\(path)/\(name)"
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true, values?.isPackage != true {
                return VaultNode(id: childPath, name: name, kind: .folder, children: children(of: url, path: childPath))
            }
            return VaultNode(id: childPath, name: name, kind: FileKind(fileName: name))
        }
    }
}
