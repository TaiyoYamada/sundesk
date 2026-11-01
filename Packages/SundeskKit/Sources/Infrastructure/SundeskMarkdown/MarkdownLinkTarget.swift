//
//  MarkdownLinkTarget.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// リンクの行き先。
public enum MarkdownLinkTarget: Equatable, Sendable {
    /// http など、アプリの外で開くもの。
    case external(URL)
    /// Vault の中のファイル（Vault のルートからのパス）。
    case vault(String)
    /// 同じノートの中の見出しなど。
    case anchor(String)
}
