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
    /// 「著者_年_題名」の形のときの著者（「SieglerLemaire」は 2 人に分ける）。
    public let authors: [Creator]
    /// 「著者_年_題名」の形のときの題名の部分（`_` は空白にする）。英語のファイル名では略していることが多い。
    public let title: String?

    public init(fileName: String) {
        let stem = (fileName as NSString).deletingPathExtension
        let parts = stem.split(whereSeparator: { $0 == "_" || $0 == "-" || $0.isWhitespace }).map(String.init)
        year = parts.lazy.compactMap { Int($0) }.first { (1900...2100).contains($0) }
        words = parts.filter { Int($0) == nil }

        let segments = stem.split(separator: "_").map(String.init)
        if segments.count >= 3, let year = Int(segments[1]), (1900...2100).contains(year) {
            authors = Self.splitNames(segments[0]).map { Creator(family: $0) }
            title = segments[2...].joined(separator: " ")
        } else {
            authors = []
            title = nil
        }
    }

    /// 「SieglerLemaire」「AmaiwaHatano」を姓ごとに分ける。小文字で始まる「deMooij」は分けない。
    private static func splitNames(_ text: String) -> [String] {
        guard text.first?.isUppercase == true, text.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [text] }
        var names: [String] = []
        var current = ""
        for character in text {
            if character.isUppercase, let last = current.last, last.isLowercase {
                names.append(current)
                current = ""
            }
            current.append(character)
        }
        names.append(current)
        return names
    }

    /// 書誌情報を検索するときの文字列。
    public var query: String {
        (words + [year.map(String.init) ?? ""]).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
