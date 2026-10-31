//
//  DocumentLink.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskMarkdown

/// メモの中で押されたリンク。
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
}
