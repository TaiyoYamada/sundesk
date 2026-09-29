//
//  SidebarDestination.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

/// サイドバーの項目。
public enum SidebarDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case notes
    case graph
    case chat
    case lab
    case images
    case models

    public var id: Self { self }

    public var title: String {
        switch self {
        case .notes: "ノート"
        case .graph: "知識グラフ"
        case .chat: "チャット"
        case .lab: "実験室"
        case .images: "画像生成"
        case .models: "モデル"
        }
    }

    /// SF Symbols の名前。
    public var systemImage: String {
        switch self {
        case .notes: "doc.text"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .chat: "bubble.left.and.text.bubble.right"
        case .lab: "flask"
        case .images: "photo.on.rectangle.angled"
        case .models: "shippingbox"
        }
    }

    public var section: SidebarSection {
        switch self {
        case .notes, .graph: .knowledge
        case .chat, .lab, .images: .ai
        case .models: .library
        }
    }

    /// 実装する予定のフェーズ（docs/requirements.md の作る順番）。
    public var plannedPhase: Int {
        switch self {
        case .notes: 1
        case .graph: 2
        case .chat: 3
        case .lab, .models: 4
        case .images: 5
        }
    }
}

public enum SidebarSection: CaseIterable, Identifiable, Sendable {
    case knowledge
    case ai
    case library

    public var id: Self { self }

    public var title: String {
        switch self {
        case .knowledge: "知識"
        case .ai: "AI"
        case .library: "ライブラリ"
        }
    }

    public var destinations: [SidebarDestination] {
        SidebarDestination.allCases.filter { $0.section == self }
    }
}
