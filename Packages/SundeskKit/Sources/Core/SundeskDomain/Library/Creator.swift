//
//  Creator.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 著者や編者 1 人。団体の名前は `family` だけに入れる。
public struct Creator: Equatable, Hashable, Codable, Sendable {
    public var family: String
    public var given: String

    public init(family: String, given: String = "") {
        self.family = family
        self.given = given
    }

    /// 1 つの文字列の名前（「Alberto Peruzzo」「Peruzzo, Alberto」「山田 大陽」）を、姓と名に分ける。
    public init(parsing name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = trimmed.firstIndex(of: ",") {
            family = trimmed[..<comma].trimmingCharacters(in: .whitespaces)
            given = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            return
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else {
            family = trimmed
            given = ""
            return
        }
        if Self.isCJK(trimmed) {
            family = words[0]
            given = words.dropFirst().joined(separator: " ")
        } else {
            family = words[words.count - 1]
            given = words.dropLast().joined(separator: " ")
        }
    }

    /// 画面に出す名前。日本語や中国語の名前は姓を先に書く。
    public var displayName: String {
        guard !given.isEmpty else { return family }
        return Self.isCJK(family) ? "\(family) \(given)" : "\(given) \(family)"
    }

    static func isCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value) }
    }
}
