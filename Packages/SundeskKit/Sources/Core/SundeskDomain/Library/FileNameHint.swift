//
//  FileNameHint.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// PDF のファイル名（「2000_Hansen_invariance-self-adaptation_PPSN.pdf」「Tsugawa_1992_暗算習熟者の数の保持.pdf」）から読める手がかり。
public struct FileNameHint: Equatable, Sendable {
    public let year: Int?
    /// 年を除いた語（`_`、`-`、空白で区切ったもの）。
    public let words: [String]

    public init(fileName: String) {
        let stem = (fileName as NSString).deletingPathExtension
        let parts = stem.split(whereSeparator: { $0 == "_" || $0 == "-" || $0.isWhitespace }).map(String.init)
        year = parts.lazy.compactMap { Int($0) }.first { (1900...2100).contains($0) }
        words = parts.filter { Int($0) == nil }
    }

    /// 書誌情報を検索するときの文字列。
    public var query: String {
        (words + [year.map(String.init) ?? ""]).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
