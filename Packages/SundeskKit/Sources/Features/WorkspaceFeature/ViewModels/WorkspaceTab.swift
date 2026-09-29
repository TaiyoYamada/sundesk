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
    }

    public let id: UUID
    public let content: Content

    public init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }

    public var title: String {
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
        }
    }

    public var systemImage: String {
        switch content {
        case .document(let path): FileIcon.systemImage(forPath: path)
        case .tool(let tool): tool.systemImage
        }
    }

    public var documentPath: String? {
        if case .document(let path) = content { path } else { nil }
    }
}
