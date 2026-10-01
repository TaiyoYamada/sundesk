//
//  CodeCompletion.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// コードの補完の候補。言語のキーワードと組み込み、本文の中の識別子、呼び出し元が足す名前から選ぶ。
enum CodeCompletion {
    /// `prefix` で始まる候補。大文字小文字も合うもの、本文と呼び出し元の名前、短いものを先にする。
    static func candidates(prefix: String, text: String, language: String, extra: [String]) -> [String] {
        let local = Set(identifiers(in: text)).union(extra)
        let builtin = Set(words(for: language)).subtracting(local)
        let lowered = prefix.lowercased()
        func matches(_ word: String) -> Bool {
            word != prefix && (prefix.isEmpty || word.lowercased().hasPrefix(lowered))
        }
        let ranked =
            local.filter(matches).map { ($0, 0) } + builtin.filter(matches).map { ($0, 1) }
        return
            ranked
            .sorted { lhs, rhs in
                let lhsExact = lhs.0.hasPrefix(prefix)
                let rhsExact = rhs.0.hasPrefix(prefix)
                if lhsExact != rhsExact { return lhsExact }
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.count != rhs.0.count { return lhs.0.count < rhs.0.count }
                return lhs.0 < rhs.0
            }
            .prefix(100)
            .map(\.0)
    }

    /// 本文の中の識別子（2 文字以上）。文字列やコメントの中の語も含む（簡単のため）。
    static func identifiers(in text: String) -> [String] {
        text.matches(of: /[A-Za-z_][A-Za-z0-9_]+/).map { String($0.output) }
    }

    /// 言語のキーワードと組み込みの名前。
    static func words(for language: String) -> [String] {
        switch language.lowercased() {
        case "python": pythonKeywords + pythonBuiltins
        default: []
        }
    }

    static let pythonKeywords = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match",
        "case", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield",
    ]

    static let pythonBuiltins = [
        "abs", "all", "any", "ascii", "bin", "bool", "breakpoint", "bytearray", "bytes", "callable", "chr",
        "classmethod", "compile", "complex", "delattr", "dict", "dir", "divmod", "enumerate", "eval", "exec",
        "filter", "float", "format", "frozenset", "getattr", "globals", "hasattr", "hash", "help", "hex", "id",
        "input", "int", "isinstance", "issubclass", "iter", "len", "list", "locals", "map", "max", "memoryview",
        "min", "next", "object", "oct", "open", "ord", "pow", "print", "property", "range", "repr", "reversed",
        "round", "set", "setattr", "slice", "sorted", "staticmethod", "str", "sum", "super", "tuple", "type", "vars",
        "zip", "Exception", "ValueError", "TypeError", "KeyError", "IndexError", "RuntimeError", "self",
    ]
}
