//
//  JSONOutput.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// CLI の --json と MCP のツールの結果に使う JSON。
enum JSONOutput {
    static func string(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(bytes: try encoder.encode(value), encoding: .utf8) ?? ""
    }
}
