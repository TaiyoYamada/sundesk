//
//  PartialDate.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 年だけ、年と月だけのこともある日付（CSL の date-parts と同じ）。
public struct PartialDate: Equatable, Hashable, Codable, Sendable {
    public var year: Int
    public var month: Int?
    public var day: Int?

    public init(year: Int, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// CSL の date-parts の 1 つ目（[年, 月, 日]）から作る。
    public init?(parts: [Int]) {
        guard let year = parts.first else { return nil }
        self.init(year: year, month: parts.count > 1 ? parts[1] : nil, day: parts.count > 2 ? parts[2] : nil)
    }

    /// 「2014」「2014-07」「2014-07-23」の形の文字列から作る。
    public init?(parsing text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        self.init(parts: parts)
    }

    /// 「2014」「2014-07」「2014-07-23」。
    public var text: String {
        [String(year), month.map { String(format: "%02d", $0) }, day.map { String(format: "%02d", $0) }]
            .compactMap { $0 }.joined(separator: "-")
    }
}
