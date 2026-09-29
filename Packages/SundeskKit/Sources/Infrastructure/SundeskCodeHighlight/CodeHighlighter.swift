//
//  CodeHighlighter.swift
//  SundeskCodeHighlight
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SwiftTreeSitter
import Synchronization
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// 色づけの単位の種類。`highlights.scm` のキャプチャ名を、この大分類にまとめる。
public enum CodeTokenKind: String, Sendable, CaseIterable {
    case keyword
    case string
    case comment
    case number
    case constant
    case function
    case type
    case property
    case variable
    case `operator`
    case punctuation
    case attribute
    case tag
    case escape
}

/// 色を付ける範囲（UTF-16 の範囲。NSString や NSTextView と同じ単位）。
public struct CodeToken: Hashable, Sendable {
    public let range: NSRange
    public let kind: CodeTokenKind

    public init(range: NSRange, kind: CodeTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// tree-sitter でコードを解析し、色づけの範囲を返す。
public final class CodeHighlighter: Sendable {
    public static let shared = CodeHighlighter()

    private let configurations = Mutex<[CodeLanguage: LanguageConfiguration?]>([:])

    public init() {}

    /// 色づけできる言語か。別名（`py`、`sh` など）も受け付ける。
    public func supports(_ language: String) -> Bool {
        CodeLanguage(name: language) != nil
    }

    public func highlight(_ code: String, language: String) -> [CodeToken] {
        guard let language = CodeLanguage(name: language), let configuration = configuration(for: language),
            let query = configuration.queries[.highlights]
        else { return [] }

        let parser = Parser()
        guard (try? parser.setLanguage(configuration.language)) != nil, let tree = parser.parse(code) else { return [] }

        let context = Predicate.Context(string: code)
        return query.execute(in: tree)
            .resolve(with: context)
            .highlights()
            .compactMap { highlight in
                CodeTokenKind(captureName: highlight.name).map { CodeToken(range: highlight.range, kind: $0) }
            }
    }

    private func configuration(for language: CodeLanguage) -> LanguageConfiguration? {
        if let cached = configurations.withLock({ $0[language] }) { return cached }
        let loaded = try? language.loadConfiguration()
        configurations.withLock { $0[language] = loaded }
        return loaded
    }
}

// MARK: - 言語

enum CodeLanguage: Hashable, Sendable {
    case swift, python, javascript, typescript, tsx, json, html, css, bash, rust, go, c, cpp, java, yaml

    init?(name: String) {
        switch name.lowercased() {
        case "swift": self = .swift
        case "python", "py": self = .python
        case "javascript", "js", "mjs", "cjs", "jsx": self = .javascript
        case "typescript", "ts": self = .typescript
        case "tsx": self = .tsx
        case "json", "jsonc": self = .json
        case "html", "htm", "xml", "svg": self = .html
        case "css": self = .css
        case "bash", "sh", "zsh", "shell", "shellscript", "console": self = .bash
        case "rust", "rs": self = .rust
        case "go", "golang": self = .go
        case "c", "h": self = .c
        case "cpp", "c++", "cc", "hpp", "cxx": self = .cpp
        case "java": self = .java
        case "yaml", "yml": self = .yaml
        default: return nil
        }
    }

    /// 文法と、色づけの規則（`highlights.scm`）を読み込む。
    ///
    /// TypeScript は JavaScript の規則、C++ は C の規則を土台にしているので、両方を合わせる。
    func loadConfiguration() throws -> LanguageConfiguration? {
        let language = Language(treeSitterLanguage)
        var sources: [String] = []
        for bundleName in queryBundles {
            guard let url = QueryFiles.highlightsURL(bundleName: bundleName),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            sources.append(text)
        }
        let query = try Query(language: language, data: Data(sources.joined(separator: "\n").utf8))
        return LanguageConfiguration(language, name: "\(self)", queries: [.highlights: query])
    }

    private var treeSitterLanguage: OpaquePointer {
        switch self {
        case .swift: tree_sitter_swift()
        case .python: tree_sitter_python()
        case .javascript: tree_sitter_javascript()
        case .typescript: tree_sitter_typescript()
        case .tsx: tree_sitter_tsx()
        case .json: tree_sitter_json()
        case .html: tree_sitter_html()
        case .css: tree_sitter_css()
        case .bash: tree_sitter_bash()
        case .rust: tree_sitter_rust()
        case .go: tree_sitter_go()
        case .c: tree_sitter_c()
        case .cpp: tree_sitter_cpp()
        case .java: tree_sitter_java()
        case .yaml: tree_sitter_yaml()
        }
    }

    /// 規則ファイルの入ったバンドルの名前（土台になる言語を先に）。
    private var queryBundles: [String] {
        switch self {
        case .swift: ["TreeSitterSwift_TreeSitterSwift"]
        case .python: ["TreeSitterPython_TreeSitterPython"]
        case .javascript: ["TreeSitterJavaScript_TreeSitterJavaScript"]
        case .typescript: ["TreeSitterJavaScript_TreeSitterJavaScript", "TreeSitterTypeScript_TreeSitterTypeScript"]
        case .tsx: ["TreeSitterJavaScript_TreeSitterJavaScript", "TreeSitterTypeScript_TreeSitterTSX"]
        case .json: ["TreeSitterJSON_TreeSitterJSON"]
        case .html: ["TreeSitterHTML_TreeSitterHTML"]
        case .css: ["TreeSitterCSS_TreeSitterCSS"]
        case .bash: ["TreeSitterBash_TreeSitterBash"]
        case .rust: ["TreeSitterRust_TreeSitterRust"]
        case .go: ["TreeSitterGo_TreeSitterGo"]
        case .c: ["TreeSitterC_TreeSitterC"]
        case .cpp: ["TreeSitterC_TreeSitterC", "TreeSitterCPP_TreeSitterCPP"]
        case .java: ["TreeSitterJava_TreeSitterJava"]
        case .yaml: ["TreeSitterYAML_TreeSitterYAML"]
        }
    }
}

// MARK: - 規則ファイルの場所

/// 文法パッケージのリソース（`queries/highlights.scm`）を探す。
///
/// swift-tree-sitter の既定の探し方は `Bundle.main` だけを見るので、`swift test` では見つからない。
/// アプリの中と、テストのときにバンドルが並ぶフォルダの両方を探す。
enum QueryFiles {
    static func highlightsURL(bundleName: String) -> URL? {
        for directory in searchDirectories {
            let bundle = directory.appending(path: "\(bundleName).bundle")
            for relative in ["queries/highlights.scm", "Contents/Resources/queries/highlights.scm"] {
                let url = bundle.appending(path: relative)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// アプリなら `sundesk.app/Contents/Resources`、テストなら `.xctest` と同じフォルダにバンドルが並ぶ。
    /// このコードが入っているバンドル（`Bundle(for:)`）を起点に探す。
    private static var searchDirectories: [URL] {
        var directories: [URL] = []
        for bundle in [Bundle(for: CodeHighlighter.self), Bundle.main] {
            if let resources = bundle.resourceURL { directories.append(resources) }
            directories.append(bundle.bundleURL)
            directories.append(bundle.bundleURL.deletingLastPathComponent())
        }
        return directories
    }
}

extension CodeTokenKind {
    /// `keyword.function` のようなキャプチャ名を、大分類に直す。知らないものは nil（色を付けない）。
    init?(captureName: String) {
        let components = captureName.split(separator: ".")
        guard let head = components.first else { return nil }
        switch head {
        case "keyword", "include", "conditional", "repeat", "exception", "storageclass", "define", "preproc":
            self = .keyword
        case "string", "character":
            self = components.contains("escape") ? .escape : components.contains("special") ? .constant : .string
        case "comment":
            self = .comment
        case "number", "float":
            self = .number
        case "boolean", "constant":
            self = .constant
        case "function", "method", "constructor":
            self = .function
        case "type", "module", "namespace":
            self = .type
        case "property", "field":
            self = .property
        case "variable", "parameter", "label":
            self = components.contains("builtin") ? .constant : components.contains("parameter") ? .variable : .variable
        case "operator":
            self = .operator
        case "punctuation":
            self = .punctuation
        case "attribute", "annotation":
            self = .attribute
        case "tag":
            self = components.contains("attribute") ? .attribute : .tag
        case "escape":
            self = .escape
        default:
            return nil
        }
    }
}
