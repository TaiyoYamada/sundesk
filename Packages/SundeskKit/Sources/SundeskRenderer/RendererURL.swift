//
//  RendererURL.swift
//  SundeskRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 描画用のページとアプリの間で使う URL。renderer/src/links.ts と対になっている。
public enum RendererURL {
    /// 同梱した renderer（HTML、JS、CSS）。
    public static let appScheme = "sundesk-app"
    /// Vault の中のファイル（画像、HTML のノートなど）。
    public static let vaultScheme = "sundesk-vault"
    /// ノートを開く指示。ページは読み込まず、アプリがタブで開く。
    public static let openScheme = "sundesk-open"

    public static let indexURL = URL(string: "\(appScheme)://renderer/index.html")!

    /// Vault のルートからのパスを、ページから読める URL にする。
    public static func vaultURL(for path: String) -> URL {
        var components = URLComponents()
        components.scheme = vaultScheme
        components.host = "vault"
        components.path = "/" + path
        return components.url!
    }

    /// `sundesk-vault://vault/…` の URL を、Vault のルートからのパスに戻す。
    public static func vaultPath(from url: URL) -> String? {
        guard url.scheme == vaultScheme else { return nil }
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    /// ノートを開く指示の中身。
    public struct OpenRequest: Equatable, Sendable {
        /// `[[...]]` の中身、または Vault のルートからのパス。
        public let target: String
        /// true なら `target` は正確なパス。
        public let isExactPath: Bool

        public init(target: String, isExactPath: Bool) {
            self.target = target
            self.isExactPath = isExactPath
        }
    }

    public static func openRequest(from url: URL) -> OpenRequest? {
        guard url.scheme == openScheme,
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let target = items.first(where: { $0.name == "target" })?.value, !target.isEmpty
        else { return nil }
        return OpenRequest(target: target, isExactPath: items.contains { $0.name == "exact" && $0.value == "1" })
    }
}

/// 同梱した renderer の置き場所。
public enum RendererAssets {
    public static var directory: URL {
        guard let url = Bundle.module.url(forResource: "Renderer", withExtension: nil) else {
            fatalError("Renderer のリソースがありません。renderer/ で npm run build を実行してください")
        }
        return url
    }
}
