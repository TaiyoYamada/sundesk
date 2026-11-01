//
//  ReferenceType.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 文献の種類。値は CSL の種類の名前。
public enum ReferenceType: String, CaseIterable, Sendable {
    case journalArticle = "article-journal"
    case conferencePaper = "paper-conference"
    /// プレプリント（CSL では article）。
    case preprint = "article"
    case book
    case bookChapter = "chapter"
    case thesis
    case report
    case webpage
    case document

    /// CSL の種類の名前か、Crossref の種類の名前（doi.org が Crossref の DOI に返すもの）から決める。
    public init(csl name: String) {
        switch name {
        case "article-journal", "journal-article": self = .journalArticle
        case "paper-conference", "proceedings-article": self = .conferencePaper
        case "article", "posted-content": self = .preprint
        case "book", "monograph", "edited-book", "reference-book": self = .book
        case "chapter", "book-chapter", "book-section", "book-part": self = .bookChapter
        case "thesis", "dissertation": self = .thesis
        case "report", "report-component": self = .report
        case "webpage", "post-weblog": self = .webpage
        default: self = .document
        }
    }
}
