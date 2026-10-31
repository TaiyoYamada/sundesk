//
//  PaperSummarizer.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 言語モデルで論文を要約する。モデルが一度に読める長さは短いので、本文を区切って少しずつ読ませる。
public protocol PaperSummarizer: Sendable {
    /// 使えないときの理由。使えるなら nil。
    func unavailableReason() -> String?
    /// 1 回に読ませる文の長さの上限（トークン）。
    func inputBudget() async -> Int
    func tokenCount(_ text: String) async throws(SummaryError) -> Int
    /// 本文の一部から、要点のメモを作る。
    func notes(on part: String, title: String) async throws(SummaryError) -> String
    /// 要点のメモから、要約を作る。
    func summary(from notes: String, title: String) async throws(SummaryError) -> PaperSummary
}

public enum SummaryError: Error, Equatable, Sendable {
    case unavailable(String)
    /// PDF がないか、文字を読めない（画像だけの PDF など）。
    case noText
    case model(String)

    public var message: String {
        switch self {
        case .unavailable(let reason): "要約できません: \(reason)"
        case .noText: "PDF から文字を読めないので、要約できません"
        case .model(let reason): "要約に失敗しました: \(reason)"
        }
    }
}

public enum SummaryProgress: Equatable, Sendable {
    /// 本文の `part` 番目（1 始まり）を読んでいる。
    case reading(part: Int, count: Int)
    case combining
    case finished(PaperSummary)
}
