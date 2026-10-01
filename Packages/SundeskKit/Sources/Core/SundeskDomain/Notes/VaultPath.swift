//
//  VaultPath.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// Vault のルートからのパスを扱う。
public enum VaultPath {
    /// ノートのある場所を基準に、相対パスを Vault のルートからのパスに直す。
    /// Vault の外を指す場合は nil。
    public static func resolve(_ relative: String, from notePath: String) -> String? {
        let pathPart = relative.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
        let decoded = pathPart.removingPercentEncoding ?? pathPart

        var segments = decoded.hasPrefix("/") ? [] : notePath.split(separator: "/").dropLast().map(String.init)
        for segment in decoded.split(separator: "/") {
            switch segment {
            case ".":
                continue
            case "..":
                guard !segments.isEmpty else { return nil }
                segments.removeLast()
            default:
                segments.append(String(segment))
            }
        }
        return segments.isEmpty ? nil : segments.joined(separator: "/")
    }
}
