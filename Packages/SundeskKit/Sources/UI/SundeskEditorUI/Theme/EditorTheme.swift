//
//  EditorTheme.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskCodeHighlight

/// エディタで使う文字の大きさと色。色はシステムの色を使い、ダークモードに合わせて変わる。
enum EditorTheme {
    // MARK: - 文字

    static let bodySize: CGFloat = 15
    static let codeSize: CGFloat = 13
    /// Markdown の 1 行の長さの上限（読みやすさのため、Obsidian と同じく幅を絞る）。
    static let readableWidth: CGFloat = 760

    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
    static var codeFont: NSFont { .monospacedSystemFont(ofSize: codeSize, weight: .regular) }

    static func headingSize(level: Int) -> CGFloat {
        switch level {
        case 1: 26
        case 2: 22
        case 3: 18
        case 4: 16
        default: bodySize
        }
    }

    static func headingFont(level: Int) -> NSFont {
        .systemFont(ofSize: headingSize(level: level), weight: level <= 2 ? .bold : .semibold)
    }

    // MARK: - 色

    static let syntaxColor = NSColor.tertiaryLabelColor
    static let linkColor = NSColor.linkColor
    static let tagColor = NSColor.controlAccentColor
    static let mathColor = NSColor.systemPurple
    static let secondaryColor = NSColor.secondaryLabelColor
    static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.08)

    /// コードブロックの色づけ（Xcode の既定に近い配色）。
    static func color(for kind: CodeTokenKind) -> NSColor {
        switch kind {
        case .keyword: .systemPink
        case .string: .systemRed
        case .comment: .systemGray
        case .number: .systemBlue
        case .constant: .systemOrange
        case .function: .systemTeal
        case .type: .systemPurple
        case .property: .systemIndigo
        case .variable, .operator: .labelColor
        case .punctuation: .secondaryLabelColor
        case .attribute: .systemBrown
        case .tag: .systemBlue
        case .escape: .systemOrange
        }
    }
}
