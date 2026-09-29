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
/// 大文字と小文字は区別しない。候補が複数あれば、浅い場所にあるものを選ぶ。
public struct LinkResolver: Sendable {
    private let paths: [String]
    private let lowercasedPaths: [String: String]

    public init(paths: some Sequence<String>) {
        let paths = Array(paths)
        self.paths = paths
        var lowercased: [String: String] = [:]
        for path in paths { lowercased[path.lowercased()] = lowercased[path.lowercased()] ?? path }
        self.lowercasedPaths = lowercased
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
        return Self.shallowest(byName)
    }

    private static func shallowest(_ candidates: [String]) -> String? {
        candidates.min { lhs, rhs in
            let (lhsDepth, rhsDepth) = (lhs.split(separator: "/").count, rhs.split(separator: "/").count)
            return lhsDepth != rhsDepth ? lhsDepth < rhsDepth : lhs < rhs
        }
    }
}
