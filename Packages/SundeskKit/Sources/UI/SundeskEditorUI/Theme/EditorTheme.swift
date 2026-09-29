//
//  EditorTheme.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskCodeHighlight
import SwiftUI

/// 閲覧とエディタで使う文字の大きさと色。色はシステムの色を使い、ダークモードに合わせて変わる。
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

    /// コードの色づけ（Xcode の既定に近い配色）。
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

    /// 注記の種類ごとのアイコンと色。
    static func callout(_ kind: String) -> (systemImage: String, color: Color) {
        switch kind {
        case "tip", "hint": ("flame", .teal)
        case "important": ("exclamationmark.circle", .purple)
        case "warning", "attention": ("exclamationmark.triangle", .orange)
        case "caution", "danger", "error": ("xmark.octagon", .red)
        case "todo": ("checklist", .blue)
        case "question", "faq", "help": ("questionmark.circle", .yellow)
        case "example": ("list.bullet.rectangle", .indigo)
        case "quote", "cite": ("quote.opening", .gray)
        case "success", "check", "done": ("checkmark.circle", .green)
        case "info": ("info.circle", .blue)
        default: ("pencil", .blue)
        }
    }
}
