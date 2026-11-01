//
//  SidebarItem.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// サイドバーの項目。論文を選ぶと PDF を、それ以外（フォルダ）を選ぶと文献の一覧を出す。
public enum SidebarItem: Hashable, Sendable {
    case all
    case unfiled
    case collection(UUID)
    case tag(String)
    /// 論文。1 本の論文がいくつものコレクションに入っているので、どのコレクションの下の行か（nil なら未整理）も持つ。
    case reference(UUID, parent: UUID?)
}
