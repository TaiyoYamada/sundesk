//
//  DocumentLink.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskMarkdown

/// ノートの中で押されたリンク。閲覧表示とエディタの両方から届く。
public enum DocumentLink: Hashable, Sendable {
    /// `[[...]]` の行き先（ファイル名やタイトル。解決はアプリが行う）。
    case note(String)
    /// Vault のルートからの正確なパス（相対リンクを解決したもの）。
    case file(String)
    /// アプリの外で開くもの（http など）。
    case external(URL)
    /// 同じノートの見出し。
    case heading(String)
    case tag(String)

    init?(_ target: MarkdownLinkTarget?) {
        switch target {
        case .external(let url): self = .external(url)
        case .vault(let path): self = .file(path)
        case .anchor(let anchor): self = .heading(anchor)
        case nil: return nil
        }
    }

    // MARK: - SwiftUI の Text に載せるための URL

    private static let scheme = "sundesk-link"

    /// SwiftUI の `Text` のリンクに使う URL。押されると `OpenURLAction` に届く。
    var url: URL {
        if case .external(let url) = self { return url }
        var components = URLComponents()
        components.scheme = Self.scheme
        let (kind, value): (String, String) =
            switch self {
            case .note(let target): ("note", target)
            case .file(let path): ("file", path)
            case .heading(let anchor): ("heading", anchor)
            case .tag(let name): ("tag", name)
            case .external(let url): ("external", url.absoluteString)
            }
        components.host = kind
        components.queryItems = [URLQueryItem(name: "value", value: value)]
        return components.url ?? URL(string: "\(Self.scheme)://invalid")!
    }

    init(url: URL) {
        guard url.scheme == Self.scheme,
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        else {
            self = .external(url)
            return
        }
        switch url.host() {
        case "note": self = .note(value)
        case "file": self = .file(value)
        case "heading": self = .heading(value)
        case "tag": self = .tag(value)
        default: self = .external(url)
        }
    }
}

/// 見出しへのリンク（`#固有値の定義`）と見出しの文字を比べる。空白と `-` の違い、大文字小文字は無視する。
public enum HeadingAnchor {
    public static func matches(_ anchor: String, heading: String) -> Bool {
        normalize(anchor.removingPercentEncoding ?? anchor) == normalize(heading)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacing(/[\s\-]+/, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
