//
//  FileSystemVaultRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

/// Mac のフォルダを Vault として読む。外のフォルダ（~/Research など）を、読むだけでつなげる。
public struct FileSystemVaultRepository: VaultRepository {
    private let root: @Sendable () -> URL
    private let mounts: @Sendable () -> [VaultMount]

    /// - Parameters:
    ///   - root: Vault のフォルダ。呼ぶたびに設定から読む。
    ///   - mounts: 読むだけでつなぐ外のフォルダ。呼ぶたびに設定から読む。
    public init(root: @escaping @Sendable () -> URL, mounts: @escaping @Sendable () -> [VaultMount] = { [] }) {
        self.root = root
        self.mounts = mounts
    }

    @concurrent
    public func loadTree() async throws(VaultError) -> VaultNode {
        let root = root().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .vaultNotFound(path: root.path)
        }
        let mounts = mounts()
        let names = Set(mounts.map(\.name))
        var children = Self.children(of: root, path: "").filter { !names.contains($0.name) }
        for mount in mounts {
            children.append(
                VaultNode(
                    id: mount.name, name: mount.name, kind: .folder,
                    children: Self.children(of: mount.url.standardizedFileURL, path: mount.name, filter: mount.filter)))
        }
        return VaultNode(id: "", name: root.lastPathComponent, kind: .folder, children: children)
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
        guard !isReadOnly(path) else { throw .readOnly(path: path) }
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

    public func isReadOnly(_ path: String) -> Bool {
        mounts().contains { $0.contains(path) }
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
        if let (mount, relative) = mount(for: path) {
            return relative.isEmpty ? mount.url : mount.url.appending(path: relative)
        }
        return root().appending(path: path)
    }

    public func changes() -> AsyncStream<Void> {
        let urls = [root()] + mounts().map(\.url)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watcher = DirectoryWatcher(urls: urls) { continuation.yield() }
            continuation.onTermination = { _ in withExtendedLifetime(watcher) {} }
        }
    }

    // MARK: - 内部

    private func mount(for path: String) -> (VaultMount, String)? {
        for mount in mounts() {
            if let relative = mount.relativePath(of: path) { return (mount, relative) }
        }
        return nil
    }

    /// Vault の中のパスをファイルの場所に直す。Vault（とつないだフォルダ）の外や、存在しないファイルは拒否する。
    private func resolve(_ path: String) throws(VaultError) -> URL {
        let base: URL
        let relative: String
        if let (mount, inside) = mount(for: path) {
            base = mount.url.standardizedFileURL
            relative = inside
        } else {
            base = root().standardizedFileURL
            relative = path
        }
        let url = base.appending(path: relative).standardizedFileURL
        guard url.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
            throw .fileNotFound(path: path)
        }
        return url
    }

    /// 木に入れないフォルダ（依存ライブラリ、ビルドの結果、キャッシュ）。隠しフォルダ（.git、.venv など）も入れない。
    private static let ignoredNames: Set<String> = [
        "node_modules", ".build", "DerivedData", "__pycache__", "build", "dist", "site-packages",
    ]

    private static func children(of directory: URL, path: String, filter: VaultMount.Filter = .all) -> [VaultNode] {
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
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            switch filter {
            case .all:
                break
            case .sections(let sections, let taggedFolders, let tags):
                // 一番上では、選んだフォルダだけを見せる。タグで選ぶフォルダは、タグの合うノートだけにする
                guard isFolder, sections.contains(name) else { return nil }
                if taggedFolders.contains(name) {
                    let notes = children(of: url, path: childPath).filter { node in
                        node.kind == .markdown && Self.hasTag(in: url.appending(path: node.name), tags: tags)
                    }
                    return notes.isEmpty ? nil : VaultNode(id: childPath, name: name, kind: .folder, children: notes)
                }
            }
            if isFolder {
                return VaultNode(id: childPath, name: name, kind: .folder, children: children(of: url, path: childPath))
            }
            return VaultNode(id: childPath, name: name, kind: FileKind(fileName: name))
        }
    }

    /// ノートのフロントマターの tags に、`tags` のどれかがあるか。
    private static func hasTag(in url: URL, tags: Set<String>) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
            let head = try? handle.read(upToCount: 4096).flatMap({ String(data: $0, encoding: .utf8) })
        else { return false }
        try? handle.close()
        guard let line = head.split(separator: "\n").first(where: { $0.hasPrefix("tags:") }) else { return false }
        let values = line.dropFirst("tags:".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
        return values.contains { tags.contains($0) }
    }
}
