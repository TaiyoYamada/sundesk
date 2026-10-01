//
//  CSVHeadReader.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// CSV の先頭だけを読む（数百 MB の表でも、最初の 256 KB しか読まない）。
public struct CSVHeadReader: ReadTableHeadUseCase {
    private let fileURL: @Sendable (String) -> URL

    public init(fileURL: @escaping @Sendable (String) -> URL) {
        self.fileURL = fileURL
    }

    @concurrent
    public func callAsFunction(path: String, rows: Int) async -> TableHead? {
        let url = fileURL(path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard var data = try? handle.read(upToCount: 256 * 1024), !data.isEmpty else { return nil }
        // 最後の行は途中で切れているかもしれない（文字の途中のこともある）ので、最後の改行までにする
        if data.count >= 256 * 1024, let end = data.lastIndex(of: UInt8(ascii: "\n")) {
            data = data[..<end]
        }
        guard let text = String(bytes: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else { return nil }
        let body = lines.dropFirst().prefix(rows).map { Self.fields(of: $0, limit: 400) }
        return TableHead(columns: Self.fields(of: header, limit: 400), rows: Array(body), size: size)
    }

    /// 1 行を列に分ける（ダブルクォートで囲んだ列の中のカンマは区切りにしない）。長すぎる列は縮める。
    static func fields(of line: String, limit: Int) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        for character in line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) {
            switch character {
            case "\"": quoted.toggle()
            case "," where !quoted:
                fields.append(current)
                current = ""
            default: current.append(character)
            }
        }
        fields.append(current)
        return fields.map { $0.count > limit ? String($0.prefix(limit)) + "…" : $0 }
    }
}
