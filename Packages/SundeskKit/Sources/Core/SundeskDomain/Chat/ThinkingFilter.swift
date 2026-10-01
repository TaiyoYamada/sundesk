//
//  ThinkingFilter.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 考える過程を出すモデル（Qwen3 など）の `<think>…</think>` を、答えから取り除く。
///
/// トークンは少しずつ届くので、タグが途中で切れていても正しく分けられるよう、確定するまで手元に残す。
public struct ThinkingFilter: Sendable {
    private static let open = "<think>"
    private static let close = "</think>"

    private var buffer = ""
    /// 考えている途中か。
    public private(set) var isThinking = false

    public init() {}

    /// 届いた文字を入れ、答えとして出してよい文字を返す。
    public mutating func feed(_ text: String) -> String {
        buffer += text
        var output = ""
        while true {
            let tag = isThinking ? Self.close : Self.open
            if let range = buffer.range(of: tag) {
                if !isThinking { output += buffer[..<range.lowerBound] }
                buffer = String(buffer[range.upperBound...])
                isThinking.toggle()
                continue
            }
            // タグの頭だけ届いているかもしれない部分は残す
            let keep = Self.partialSuffixLength(of: buffer, tag: tag)
            let ready = buffer.dropLast(keep)
            if !isThinking { output += ready }
            buffer = String(buffer.suffix(keep))
            return output
        }
    }

    /// 最後に残った文字（考えている途中で終わったら捨てる）。
    public mutating func finish() -> String {
        defer { buffer = "" }
        return isThinking ? "" : buffer
    }

    private static func partialSuffixLength(of text: String, tag: String) -> Int {
        for length in stride(from: min(tag.count - 1, text.count), to: 0, by: -1)
        where tag.hasPrefix(text.suffix(length)) {
            return length
        }
        return 0
    }
}
