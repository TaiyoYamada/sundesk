//
//  SidebarNode.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// サイドバーの木の 1 行（コレクション、未整理、論文）。
public struct SidebarNode: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case collection
        case unfiled
        case reference(hasPDF: Bool)
    }

    public let id: SidebarItem
    public let name: String
    public let kind: Kind
    /// 中のコレクションと論文。開けない行（論文）は nil。
    public let children: [SidebarNode]?
}
