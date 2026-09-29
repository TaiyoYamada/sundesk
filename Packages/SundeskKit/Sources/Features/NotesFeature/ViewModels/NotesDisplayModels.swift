//
//  NotesDisplayModels.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

// View に渡す表示用の型。View は Domain の型を直接扱わず、これだけを使う。

/// ナビゲータのファイルの木の 1 行。
public struct NavigatorItem: Identifiable, Hashable, Sendable {
    /// Vault のルートからのパス。
    public let id: String
    public let name: String
    public let systemImage: String
    public let isFolder: Bool
    public let children: [NavigatorItem]?

    init(node: VaultNode) {
        id = node.path
        name = node.name
        systemImage = FileIcon.systemImage(for: node.kind)
        isFolder = node.isFolder
        children = node.children?.map(NavigatorItem.init)
    }
}

/// 他のノートへの参照（バックリンク、タグのノートなど）。
public struct NoteLinkItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String

    init(_ summary: NoteSummary) {
        path = summary.path
        title = summary.title
    }
}

public struct SearchResultItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let snippet: String

    init(_ result: SearchResult) {
        path = result.path
        title = result.title
        snippet = result.snippet
    }
}

public struct TagItem: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int

    init(_ tag: TagCount) {
        name = tag.name
        count = tag.count
    }
}

public struct PropertyItem: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: String
}

/// 目次の 1 項目。
public struct OutlineItem: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    /// 何番目の見出しか（0 始まり）。
    public let index: Int
    public let level: Int
    public let title: String
    /// ファイル全体での行番号（1 始まり）。
    public let line: Int

    public init(index: Int, level: Int, title: String, line: Int) {
        self.index = index
        self.level = level
        self.title = title
        self.line = line
    }
}

/// インスペクタの「ファイル」に出す情報（表示用に整えた文字列）。
public struct FileInfoItem: Equatable, Sendable {
    public let name: String
    public let kind: String
    public let size: String
    public let created: String?
    public let modified: String
    public let location: String
}

/// 開いたファイルを、どう描くか。判断は ViewModel が行い、View はこれに従って描くだけ。
/// 編集する本文は `DocumentViewModel.text` から読む。
public enum DocumentDisplay: Equatable, Sendable {
    case loading
    case failed(message: String)
    /// Markdown を編集する。`livePreview` なら、カーソルのない行の記号を隠す。
    case markdownEditor(livePreview: Bool)
    /// Markdown を整形して読む。`vaultRoot` は、ノートから読む画像などの置き場所。
    case markdownReading(vaultRoot: URL)
    /// HTML ファイルをそのまま描く。`vaultRoot` は、HTML から読む画像などの置き場所。
    case htmlPage(vaultRoot: URL)
    /// コードやテキストを編集する。`language` が nil なら色づけしない。
    case codeEditor(language: String?)
    case image(URL)
    case pdf(URL)
    /// その他のファイルを Quick Look で描く。
    case quickLook(URL)
}

/// ファイルの種類ごとのアイコン（SF Symbols）と名前。
public enum FileIcon {
    public static func systemImage(forPath path: String) -> String {
        systemImage(for: FileKind(fileName: path.split(separator: "/").last.map(String.init) ?? path))
    }

    static func systemImage(for kind: FileKind) -> String {
        switch kind {
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

    static func displayName(for kind: FileKind) -> String {
        switch kind {
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

extension VaultError {
    /// 利用者に見せるメッセージ。
    var message: String {
        switch self {
        case .fileNotFound: "ファイルが見つかりません。移動したか、削除された可能性があります。"
        case .vaultNotFound(let path): "Vault のフォルダが見つかりません（\(path)）。"
        case .unreadable(_, let reason): "ファイルを読めませんでした: \(reason)"
        case .unwritable(_, let reason): "ファイルを保存できませんでした: \(reason)"
        case .readOnly: "このファイルは読むだけです（~/Research や study-artifact のファイルは、元の場所で編集します）。"
        }
    }
}
