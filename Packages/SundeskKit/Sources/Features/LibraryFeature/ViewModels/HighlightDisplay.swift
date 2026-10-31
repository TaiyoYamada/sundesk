//
//  HighlightDisplay.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import CoreGraphics
import Foundation
import SundeskDomain

/// PDF の上に描くハイライトと、注釈の一覧の 1 行。
public struct HighlightDisplay: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let color: HighlightColor
    public let text: String
    public let comment: String
    public let rects: [HighlightRect]

    init(_ annotation: Annotation) {
        id = annotation.id
        color = HighlightColor(annotation.color)
        text = annotation.text
        comment = annotation.comment
        rects = annotation.rects.map {
            HighlightRect(pageIndex: $0.pageIndex, rect: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
        }
    }

    /// 「p. 3」。
    public var pageLabel: String {
        "p. \((rects.first?.pageIndex ?? 0) + 1)"
    }
}

/// ページの中の四角（PDF のページの座標）。
public struct HighlightRect: Equatable, Sendable {
    public let pageIndex: Int
    public let rect: CGRect

    public init(pageIndex: Int, rect: CGRect) {
        self.pageIndex = pageIndex
        self.rect = rect
    }
}
