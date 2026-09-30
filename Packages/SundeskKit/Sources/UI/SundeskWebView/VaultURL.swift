//
//  VaultURL.swift
//  SundeskWebView
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// HTML のページから Vault のファイルを読むための URL（`sundesk-vault://vault/<パス>`）。
nonisolated public enum VaultURL {
    public static let scheme = "sundesk-vault"

    /// Vault のルートからのパスを、ページから読める URL にする。
    public static func url(for path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "vault"
        components.path = "/" + path
        return components.url!
    }

    /// `sundesk-vault://vault/…` の URL を、Vault のルートからのパスに戻す。
    public static func path(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}
