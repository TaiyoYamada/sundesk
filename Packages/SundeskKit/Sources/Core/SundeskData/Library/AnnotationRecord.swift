//
//  AnnotationRecord.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SwiftData

/// 注釈（``Annotation``）の保存の形。
@Model
final class AnnotationRecord {
    @Attribute(.unique) var id: UUID
    var reference: ReferenceRecord?
    var color: String
    var text: String
    var comment: String
    /// [AnnotationRect] の JSON。
    var rects: Data
    var dateAdded: Date

    init(id: UUID) {
        self.id = id
        color = ""
        text = ""
        comment = ""
        rects = Data()
        dateAdded = .now
    }
}
