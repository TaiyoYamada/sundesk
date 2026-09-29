//
//  AnalyzeNoteUseCase.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 編集中のノートを解析し直す（目次、タグ、プロパティを書いたそばから更新する）。
public protocol AnalyzeNoteUseCase: Sendable {
    func callAsFunction(_ source: String, path: String) -> NoteAnalysis
}

public struct AnalyzeNoteInteractor: AnalyzeNoteUseCase {
    private let markdown: any MarkdownParsing

    public init(markdown: any MarkdownParsing) {
        self.markdown = markdown
    }

    public func callAsFunction(_ source: String, path: String) -> NoteAnalysis {
        markdown.analyze(source, path: path)
    }
}
