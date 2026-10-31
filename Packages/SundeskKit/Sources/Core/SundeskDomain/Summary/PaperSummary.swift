//
//  PaperSummary.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// オンデバイスのモデルで作った、論文の要約。
public struct PaperSummary: Equatable, Codable, Sendable {
    /// 何を解こうとしているか。
    public var purpose: String
    /// どう解いたか。
    public var method: String
    /// 何が分かったか。
    public var results: String
    /// 限界や、残っている課題。
    public var limitations: String
    public var createdAt: Date

    public init(purpose: String, method: String, results: String, limitations: String, createdAt: Date = .now) {
        self.purpose = purpose
        self.method = method
        self.results = results
        self.limitations = limitations
        self.createdAt = createdAt
    }
}
