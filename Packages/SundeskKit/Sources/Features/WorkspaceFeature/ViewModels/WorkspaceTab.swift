//
//  WorkspaceTab.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import NotesFeature

/// エディタの 1 つのタブ。
public struct WorkspaceTab: Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        /// Vault のルートからのパス。
        case document(String)
        case tool(WorkspaceTool)
        /// 論文（キー）。
        case paper(String)
        /// 実験（キー）。
        case experiment(String)
        /// 実験を並べて比べる（キーの並び）。
        case comparison([String])
    }

    public let id: UUID
    public let content: Content
    /// 論文や実験の題名（タブに出す）。
    public var customTitle: String?

    public init(id: UUID = UUID(), content: Content, title: String? = nil) {
        self.id = id
        self.content = content
        self.customTitle = title
    }

    public var title: String {
        if let customTitle { return customTitle }
        switch content {
        case .document(let path):
            let name = path.split(separator: "/").last.map(String.init) ?? path
            // Markdown は拡張子を出さない（Obsidian と同じ）
            for suffix in [".md", ".markdown"] where name.lowercased().hasSuffix(suffix) {
                return String(name.dropLast(suffix.count))
            }
            return name
        case .tool(let tool):
            return tool.title
        case .paper(let key), .experiment(let key):
            return key
        case .comparison(let keys):
            return "\(keys.count) 件の比較"
        }
    }

    public var systemImage: String {
        switch content {
        case .document(let path): FileIcon.systemImage(forPath: path)
        case .tool(let tool): tool.systemImage
        case .paper: "doc.text.magnifyingglass"
        case .experiment: "testtube.2"
        case .comparison: "chart.xyaxis.line"
        }
    }

    /// タブの中で編集するノート（論文と実験は、そのメモ）。インスペクタや保存に使う。
    public var documentPath: String? {
        switch content {
        case .document(let path): path
        case .paper(let key): "Papers/\(key)/note.md"
        case .experiment(let key): "Experiments/\(key)/note.md"
        case .tool, .comparison: nil
        }
    }
}
