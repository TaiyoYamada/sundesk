//
//  NoteAnalysis.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// Markdown のノートを解析した結果。
public struct NoteAnalysis: Hashable, Sendable {
    /// フロントマターの `title`、なければ最初の `# 見出し`。どちらもなければ nil。
    public let title: String?
    public let properties: [NoteProperty]
    public let tags: [String]
    public let links: [NoteLinkReference]
    /// 見出しの一覧（目次に使う）。
    public let headings: [NoteHeading]
    /// フロントマターを除いた本文。検索に使う。
    public let body: String

    public init(
        title: String?,
        properties: [NoteProperty],
        tags: [String],
        links: [NoteLinkReference],
        headings: [NoteHeading] = [],
        body: String
    ) {
        self.title = title
        self.properties = properties
        self.tags = tags
        self.links = links
        self.headings = headings
        self.body = body
    }
}

/// 見出し。`line` はファイル全体での 1 始まりの行番号。
public struct NoteHeading: Hashable, Sendable {
    public let level: Int
    public let text: String
    public let line: Int

    public init(level: Int, text: String, line: Int) {
        self.level = level
        self.text = text
        self.line = line
    }
}

/// Markdown を解析する。実装は Infrastructure 層（SundeskMarkdown）にある。
public protocol MarkdownParsing: Sendable {
    func analyze(_ source: String, path: String) -> NoteAnalysis
}

/// フロントマターの 1 項目。
public struct NoteProperty: Hashable, Sendable {
    public let key: String
    public let value: PropertyValue

    public init(key: String, value: PropertyValue) {
        self.key = key
        self.value = value
    }
}

public enum PropertyValue: Hashable, Sendable {
    case text(String)
    case list([String])

    public var displayString: String {
        switch self {
        case .text(let text): text
        case .list(let items): items.joined(separator: ", ")
        }
    }
}

/// 本文に書かれたリンク。
public struct NoteLinkReference: Hashable, Sendable {
    /// `[[...]]` の中身（`#見出し` と表示名を除いたもの）、または相対リンクを Vault のパスに直したもの。
    public let target: String
    /// true なら `target` は Vault のルートからの正確なパス（相対リンクから作ったもの）。
    public let isExactPath: Bool

    public init(target: String, isExactPath: Bool) {
        self.target = target
        self.isExactPath = isExactPath
    }
}
