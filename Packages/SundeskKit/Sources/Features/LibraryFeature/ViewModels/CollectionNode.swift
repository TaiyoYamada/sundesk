//
//  CollectionNode.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// サイドバーに出すコレクションの木。
public struct CollectionNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// 中のコレクション。なければ nil（`List` の `children:` で、開く三角を出さないため）。
    public let children: [CollectionNode]?
}
