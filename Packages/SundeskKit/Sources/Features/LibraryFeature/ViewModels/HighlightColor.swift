//
//  HighlightColor.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
import SundeskDomain
import SwiftUI

/// ハイライトの色。
public enum HighlightColor: String, CaseIterable, Identifiable, Hashable, Sendable {
    case yellow
    case red
    case green
    case blue
    case purple

    public var id: Self { self }

    init(_ color: AnnotationColor) {
        switch color {
        case .yellow: self = .yellow
        case .red: self = .red
        case .green: self = .green
        case .blue: self = .blue
        case .purple: self = .purple
        }
    }

    var annotationColor: AnnotationColor {
        switch self {
        case .yellow: .yellow
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }

    public var title: String {
        switch self {
        case .yellow: "黄"
        case .red: "赤"
        case .green: "緑"
        case .blue: "青"
        case .purple: "紫"
        }
    }

    public var nsColor: NSColor {
        switch self {
        case .yellow: .systemYellow
        case .red: .systemRed
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        }
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }
}
