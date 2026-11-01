//
//  ReferenceTypeOption.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 文献の種類の選択肢。
nonisolated public enum ReferenceTypeOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    case journalArticle
    case conferencePaper
    case preprint
    case book
    case bookChapter
    case thesis
    case report
    case webpage
    case document

    public var id: Self { self }

    init(_ type: ReferenceType) {
        switch type {
        case .journalArticle: self = .journalArticle
        case .conferencePaper: self = .conferencePaper
        case .preprint: self = .preprint
        case .book: self = .book
        case .bookChapter: self = .bookChapter
        case .thesis: self = .thesis
        case .report: self = .report
        case .webpage: self = .webpage
        case .document: self = .document
        }
    }

    var type: ReferenceType {
        switch self {
        case .journalArticle: .journalArticle
        case .conferencePaper: .conferencePaper
        case .preprint: .preprint
        case .book: .book
        case .bookChapter: .bookChapter
        case .thesis: .thesis
        case .report: .report
        case .webpage: .webpage
        case .document: .document
        }
    }

    public var title: String {
        switch self {
        case .journalArticle: "雑誌論文"
        case .conferencePaper: "会議論文"
        case .preprint: "プレプリント"
        case .book: "本"
        case .bookChapter: "本の章"
        case .thesis: "学位論文"
        case .report: "報告書"
        case .webpage: "ウェブページ"
        case .document: "文書"
        }
    }

    /// 載った先の欄の名前。
    public var containerLabel: String {
        switch self {
        case .journalArticle: "雑誌"
        case .conferencePaper: "会議録"
        case .bookChapter: "本の題名"
        case .preprint, .book, .thesis, .report, .webpage, .document: "掲載先"
        }
    }

    /// 出版社の欄の名前。
    public var publisherLabel: String {
        switch self {
        case .thesis: "大学"
        case .report: "機関"
        case .journalArticle, .conferencePaper, .preprint, .book, .bookChapter, .webpage, .document: "出版社"
        }
    }
}
