//
//  WorkspaceTab.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

/// エディタの 1 つのタブ。
public struct WorkspaceTab: Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        /// Vault のルートからのパス。
        case document(String)
        case feature(WorkspaceFeature)
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
            return FileKind(fileName: name) == .markdown
                ? String(name.dropLast(name.hasSuffix(".markdown") ? 9 : 3)) : name
        case .feature(let feature):
            return feature.title
        }
    }

    public var systemImage: String {
        switch content {
        case .document(let path): FileKind(fileName: path).systemImage
        case .feature(let feature): feature.systemImage
        }
    }

    public var documentPath: String? {
        if case .document(let path) = content { path } else { nil }
    }
}

extension FileKind {
    /// SF Symbols の名前。
    public var systemImage: String {
        switch self {
        case .folder: "folder"
        case .markdown: "doc.richtext"
        case .html: "globe"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "doc.plaintext"
        case .image: "photo"
        case .pdf: "doc.text.image"
        case .other: "doc"
        }
    }

    /// インスペクタに出す種類の名前。
    public var displayName: String {
        switch self {
        case .folder: "フォルダ"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .code(let language): "コード（\(language)）"
        case .text: "テキスト"
        case .image: "画像"
        case .pdf: "PDF"
        case .other: "その他"
        }
    }
}
