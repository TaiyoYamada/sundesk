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
}
