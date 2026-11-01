//
//  CollectionChoice.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 「コレクションに追加」のメニューに出す、平らにしたコレクション。
public struct CollectionChoice: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// 親からの道のり（「研究 / 最適化」）。
    public let path: String
}
