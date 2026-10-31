//
//  CollectionRecord.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SwiftData

/// コレクション（``ReferenceCollection``）の保存の形。
@Model
final class CollectionRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var parent: CollectionRecord?
    @Relationship(deleteRule: .cascade, inverse: \CollectionRecord.parent) var children: [CollectionRecord] = []
    var references: [ReferenceRecord] = []

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
