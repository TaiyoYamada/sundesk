//
//  LinkResolver.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// `[[リンク先]]` を、Vault の中の実際のファイルのパスに結びつける。
///
/// Obsidian と同じく、次の順に探す。
/// 1. Vault のルートからのパスとして完全に一致するもの（`.md` は省略できる）
/// 2. パスの末尾が一致するもの（`線形代数/ベクトル` → `数学/線形代数/ベクトル.md`）
/// 3. ファイル名（または拡張子を除いた名前）が一致するもの
/// 4. フォルダのメモ（`論文のキー/note.md`）のフォルダ名か題名が一致するもの
/// 大文字と小文字は区別しない。候補が複数あれば、浅い場所にあるものを選ぶ。
///
/// 論文と実験のメモはどれも `note.md` という名前なので、フォルダ名と題名でも辿れるようにしている。
public struct LinkResolver: Sendable {
    private let paths: [String]
    private let lowercasedPaths: [String: String]
    private let lowercasedTitles: [String: String]

    /// - Parameters:
    ///   - paths: Vault の中のファイルのパス。
    ///   - titles: フォルダのメモの題名 → パス（``FolderNote/titles(in:vault:markdown:)`` で集める）。
    public init(paths: some Sequence<String>, titles: [String: String] = [:]) {
        let paths = Array(paths)
        self.paths = paths
        var lowercased: [String: String] = [:]
        for path in paths { lowercased[path.lowercased()] = lowercased[path.lowercased()] ?? path }
        self.lowercasedPaths = lowercased
        var lowercasedTitles: [String: String] = [:]
        for (title, path) in titles.sorted(by: { $0.value < $1.value }) {
            let key = title.trimmingCharacters(in: .whitespaces).lowercased()
            lowercasedTitles[key] = lowercasedTitles[key] ?? path
        }
        self.lowercasedTitles = lowercasedTitles
    }

    public func resolve(_ reference: NoteLinkReference) -> String? {
        resolve(reference.target, exact: reference.isExactPath)
    }

    public func resolve(_ target: String, exact: Bool = false) -> String? {
        var target = target.trimmingCharacters(in: .whitespaces)
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        while target.hasPrefix("/") { target.removeFirst() }
        guard !target.isEmpty else { return nil }

        let lowercased = target.lowercased()
        if let path = lowercasedPaths[lowercased] { return path }
        if exact { return nil }
        if let path = lowercasedPaths[lowercased + ".md"] { return path }

        let suffixes = ["/" + lowercased, "/" + lowercased + ".md"]
        let bySuffix = paths.filter { path in suffixes.contains { path.lowercased().hasSuffix($0) } }
        if let best = Self.shallowest(bySuffix) { return best }

        let name = lowercased.split(separator: "/").last.map(String.init) ?? lowercased
        let byName = paths.filter { path in
            let fileName = (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
            return fileName == name || fileName == name + ".md"
        }
        if let best = Self.shallowest(byName) { return best }

        if let path = lowercasedPaths[lowercased + "/" + FolderNote.fileName] { return path }
        let folderSuffix = "/" + lowercased + "/" + FolderNote.fileName
        if let best = Self.shallowest(paths.filter { $0.lowercased().hasSuffix(folderSuffix) }) { return best }
        return lowercasedTitles[lowercased]
    }

    private static func shallowest(_ candidates: [String]) -> String? {
        candidates.min { lhs, rhs in
            let (lhsDepth, rhsDepth) = (lhs.split(separator: "/").count, rhs.split(separator: "/").count)
            return lhsDepth != rhsDepth ? lhsDepth < rhsDepth : lhs < rhs
        }
    }
}

/// 論文や実験のフォルダの中のメモ（`note.md`）。
public enum FolderNote {
    public static let fileName = "note.md"

    public static func isFolderNote(_ path: String) -> Bool {
        path.split(separator: "/").count >= 2 && path.lowercased().hasSuffix("/" + fileName)
    }

    /// フォルダのメモの題名 → パス。題名のないメモは含めない。
    public static func titles(
        in paths: some Sequence<String>, vault: any VaultRepository, markdown: any MarkdownParsing
    ) async -> [String: String] {
        var titles: [String: String] = [:]
        for path in paths where isFolderNote(path) {
            guard let source = try? await vault.readText(at: path),
                let title = markdown.analyze(source, path: path).title, !title.isEmpty
            else { continue }
            titles[title] = titles[title] ?? path
        }
        return titles
    }
}
