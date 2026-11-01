//
//  ReferenceCollection.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 文献をまとめるコレクション。中にコレクションを入れられる。1 件の文献は、いくつのコレクションに入ってもよい。
public struct ReferenceCollection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

extension [ReferenceCollection] {
    /// `id` のコレクションと、その中に入っているすべてのコレクションの ID。
    public func descendantIDs(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var frontier = [id]
        while let current = frontier.popLast() {
            for child in self where child.parentID == current && !result.contains(child.id) {
                result.insert(child.id)
                frontier.append(child.id)
            }
        }
        return result
    }

    /// 親からたどった「親/子」の形の名前。
    public func path(of id: UUID) -> String {
        var names: [String] = []
        var current = first { $0.id == id }
        while let collection = current {
            names.insert(collection.name, at: 0)
            current = collection.parentID.flatMap { parentID in first { $0.id == parentID } }
        }
        return names.joined(separator: "/")
    }

    /// 名前で探す。「親/子」の形なら道筋がそのとおりのものを、そうでなければその名前のものをすべて返す。
    public func matching(_ name: String) -> [ReferenceCollection] {
        if name.contains("/") {
            return filter { path(of: $0.id) == name }
        }
        return filter { $0.name == name }
    }
}
