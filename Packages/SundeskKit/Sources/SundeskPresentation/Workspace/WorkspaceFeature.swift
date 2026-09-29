//
//  WorkspaceFeature.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

/// ファイル以外に、タブで開ける機能。
public enum WorkspaceFeature: String, CaseIterable, Identifiable, Codable, Sendable {
    case graph
    case chat
    case lab
    case images
    case models

    public var id: Self { self }

    public var title: String {
        switch self {
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
        case .graph: "point.3.connected.trianglepath.dotted"
        case .chat: "bubble.left.and.text.bubble.right"
        case .lab: "flask"
        case .images: "photo.on.rectangle.angled"
        case .models: "shippingbox"
        }
    }

    /// 実装する予定のフェーズ（docs/requirements.md の作る順番）。
    public var plannedPhase: Int {
        switch self {
        case .graph: 2
        case .chat: 3
        case .lab, .models: 4
        case .images: 5
        }
    }
}
