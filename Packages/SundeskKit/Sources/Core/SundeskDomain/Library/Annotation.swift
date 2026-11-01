//
//  Annotation.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// PDF に付けたハイライトとコメント。PDF のファイルには書き込まず、ライブラリに持つ。
public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let referenceID: UUID
    public var color: AnnotationColor
    /// ハイライトした文。
    public var text: String
    public var comment: String
    /// ハイライトの範囲（行ごとの四角）。
    public var rects: [AnnotationRect]
    public var dateAdded: Date

    public init(
        id: UUID = UUID(), referenceID: UUID, color: AnnotationColor, text: String, comment: String = "",
        rects: [AnnotationRect], dateAdded: Date = .now
    ) {
        self.id = id
        self.referenceID = referenceID
        self.color = color
        self.text = text
        self.comment = comment
        self.rects = rects
        self.dateAdded = dateAdded
    }

    /// 最初の行のあるページ（0 始まり）。
    public var pageIndex: Int {
        rects.first?.pageIndex ?? 0
    }
}

/// ページの中の四角。座標は PDF のページの座標（左下が原点、単位はポイント）。
public struct AnnotationRect: Equatable, Hashable, Codable, Sendable {
    public var pageIndex: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(pageIndex: Int, x: Double, y: Double, width: Double, height: Double) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AnnotationColor: String, CaseIterable, Sendable {
    case yellow
    case red
    case green
    case blue
    case purple
}
