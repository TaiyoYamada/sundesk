//
//  FoundationModelsSummarizer.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import FoundationModels
import SundeskDomain

/// Apple のオンデバイスモデル（Foundation Models）で論文を要約する。
public struct FoundationModelsSummarizer: PaperSummarizer {
    /// 指示、プロンプトの前置き、答え（最大で 800 トークン）のために空けておく長さ。
    private static let reserved = 1400

    private var model: SystemLanguageModel { .default }

    public init() {}

    public func unavailableReason() -> String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence が有効になっていません"
        case .unavailable(.deviceNotEligible): "この Mac では使えません"
        case .unavailable(.modelNotReady): "モデルの準備ができていません（ダウンロード中など）"
        case .unavailable: "使えません"
        }
    }

    public func inputBudget() async -> Int {
        max(model.contextSize - Self.reserved, 1000)
    }

    public func tokenCount(_ text: String) async throws(SummaryError) -> Int {
        do {
            return try await model.tokenCount(for: text)
        } catch {
            throw .model(error.localizedDescription)
        }
    }

    public func notes(on part: String, title: String) async throws(SummaryError) -> String {
        let session = LanguageModelSession(
            model: model,
            instructions: """
                あなたは研究者が論文を読むのを手伝う。渡された論文の一部から、目的、手法、結果、限界に関わる要点を、\
                日本語の短い箇条書きで書き出す。数式、記号、手法の名前は原文のまま残す。本文に書かれていないことは書かない。
                """)
        do {
            let response = try await session.respond(
                to: "論文「\(title)」の一部:\n\n\(part)", options: GenerationOptions(maximumResponseTokens: 400))
            return response.content
        } catch {
            throw .model(error.localizedDescription)
        }
    }

    public func summary(from notes: String, title: String) async throws(SummaryError) -> PaperSummary {
        let session = LanguageModelSession(
            model: model,
            instructions: """
                あなたは研究者が論文を読むのを手伝う。論文の各部分から書き出した要点のメモをもとに、論文全体の要約を日本語で書く。\
                メモに書かれていないことは書かない。
                """)
        do {
            let response = try await session.respond(
                to: "論文「\(title)」の要点のメモ:\n\n\(notes)", generating: GeneratedSummary.self,
                options: GenerationOptions(maximumResponseTokens: 800))
            let content = response.content
            return PaperSummary(
                purpose: content.purpose, method: content.method, results: content.results,
                limitations: content.limitations)
        } catch {
            throw .model(error.localizedDescription)
        }
    }
}

@Generable
struct GeneratedSummary {
    @Guide(description: "この論文が解こうとしている問題と目的。日本語で 2〜3 文。")
    var purpose: String
    @Guide(description: "提案する手法や、問題への取り組み方。日本語で 2〜4 文。")
    var method: String
    @Guide(description: "主な結果と、分かったこと。数値があれば含める。日本語で 2〜4 文。")
    var results: String
    @Guide(description: "限界や、残っている課題。メモに書かれていなければ「本文には書かれていない」。日本語で 1〜3 文。")
    var limitations: String
}
