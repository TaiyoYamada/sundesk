//
//  CollectionItem.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

/// コレクションと、その中（中のコレクションも含む）の文献の数。
struct CollectionItem: Codable {
    /// 「親/子」の形の名前。
    let path: String
    let count: Int
}
