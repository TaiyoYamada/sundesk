//
//  VaultNode.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// Vault のファイルとフォルダの木。`id` は Vault のルートからのパス（ルートは空文字）。
public struct VaultNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: FileKind
    /// フォルダなら子の一覧（空のフォルダは空配列）。ファイルなら nil。
    public let children: [VaultNode]?

    public init(id: String, name: String, kind: FileKind, children: [VaultNode]? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.children = children.map(Self.sorted)
    }

    public var path: String { id }
    public var isFolder: Bool { kind == .folder }

    /// 拡張子を除いた名前。Markdown のノート名として使う。
    public var stem: String {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// 木に含まれるすべてのファイル（フォルダは含まない）。
    public var files: [VaultNode] {
        guard let children else { return [self] }
        return children.flatMap(\.files)
    }

    public func node(at path: String) -> VaultNode? {
        if id == path { return self }
        return children?.lazy.compactMap { $0.node(at: path) }.first
    }

    /// 名前に `query` を含むファイルと、それを含むフォルダだけを残した木。
    public func filtered(by query: String) -> VaultNode? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return self }
        guard let children else {
            return name.localizedStandardContains(query) ? self : nil
        }
        let kept = children.compactMap { $0.filtered(by: query) }
        return kept.isEmpty && !id.isEmpty ? nil : VaultNode(id: id, name: name, kind: kind, children: kept)
    }

    /// フォルダを先に、名前は Finder と同じ順（数字を数として比べる）に並べる。
    private static func sorted(_ nodes: [VaultNode]) -> [VaultNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// ファイルの基本情報。
public struct FileInfo: Hashable, Sendable {
    public let path: String
    public let size: Int
    public let created: Date?
    public let modified: Date

    public init(path: String, size: Int, created: Date?, modified: Date) {
        self.path = path
        self.size = size
        self.created = created
        self.modified = modified
    }
}

public enum VaultError: Error, Sendable, Equatable {
    case vaultNotFound(path: String)
    case fileNotFound(path: String)
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)
    /// 読むだけでつないだフォルダ（~/Research など）には書き込まない。
    case readOnly(path: String)
}
