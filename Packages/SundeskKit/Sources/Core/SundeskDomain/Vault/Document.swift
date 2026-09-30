//
//  Document.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 開いたファイル。
public struct Document: Sendable, Equatable {
    public let path: String
    public let name: String
    public let kind: FileKind
    public let info: FileInfo
    public let content: DocumentContent

    public init(path: String, name: String, kind: FileKind, info: FileInfo, content: DocumentContent) {
        self.path = path
        self.name = name
        self.kind = kind
        self.info = info
        self.content = content
    }

    /// 画面に出す名前。Markdown ならノートのタイトル。
    public var title: String {
        if case .markdown(_, let analysis) = content, let title = analysis.title { return title }
        return name
    }
}

public enum DocumentContent: Sendable, Equatable {
    case markdown(source: String, analysis: NoteAnalysis)
    case html(source: String, url: URL)
    case text(source: String)
    case image(URL)
    case pdf(URL)
    /// ノートブック。`source` は JSON のまま、`notebook` は読んだもの。
    case notebook(source: String, notebook: Notebook)
    case other(URL)

    /// ソース表示に使うテキスト。
    public var source: String? {
        switch self {
        case .markdown(let source, _), .html(let source, _), .text(let source), .notebook(let source, _): source
        case .image, .pdf, .other: nil
        }
    }
}
