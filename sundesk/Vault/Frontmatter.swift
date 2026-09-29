import Foundation

/// ノート先頭の YAML フロントマター。
///
/// YAML の完全な実装ではなく、Obsidian のプロパティで使われる範囲
/// （スカラー・インライン配列・ブロック配列）だけを解釈する。
/// 入れ子のマップなど解釈できない値は `.raw` として原文のまま保持し、
/// 書き戻しで壊さないようにしている。
nonisolated struct Frontmatter: Hashable, Sendable {
    enum Value: Hashable, Sendable {
        case string(String)
        case list([String])
        /// キー行より下のインデントされた行を、そのまま保持したもの。
        case raw(String)

        /// 表示や検索に使う文字列表現。
        var displayString: String {
            switch self {
            case .string(let s): s
            case .list(let items): items.joined(separator: ", ")
            case .raw(let text): text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    struct Entry: Hashable, Sendable {
        var key: String
        var value: Value
    }

    var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }
    var keys: [String] { entries.map(\.key) }

    subscript(key: String) -> Value? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue {
                    entries[index].value = newValue
                } else {
                    entries.remove(at: index)
                }
            } else if let newValue {
                entries.append(Entry(key: key, value: newValue))
            }
        }
    }

    /// スカラーならその値、配列なら先頭要素。空文字は nil として扱う。
    func string(_ key: String) -> String? {
        let value: String? = switch self[key] {
        case .string(let s): s
        case .list(let items): items.first
        case .raw, nil: nil
        }
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// 配列ならその要素、スカラーなら 1 要素の配列。
    func list(_ key: String) -> [String] {
        switch self[key] {
        case .list(let items): items
        case .string(let s) where !s.isEmpty: [s]
        default: []
        }
    }
}

// MARK: - 分割

extension Frontmatter {
    /// ファイル全体をフロントマター部分と本文に分ける。
    /// フロントマターが無ければ `yaml` は nil で、本文はファイル全体になる。
    static func split(_ content: String) -> (yaml: String?, body: String) {
        guard content.hasPrefix("---") else { return (nil, content) }
        var lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, content) }
        lines.removeFirst()

        guard let closing = lines.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return t == "---" || t == "..."
        }) else { return (nil, content) }

        let yaml = lines[..<closing].map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return (yaml.joined(separator: "\n"), body)
    }

    /// フロントマターと本文からファイル全体を組み立てる。
    static func compose(_ frontmatter: Frontmatter, body: String) -> String {
        guard !frontmatter.isEmpty else { return body }
        return "---\n" + frontmatter.serialized() + "\n---\n" + body
    }
}

// MARK: - 解釈

extension Frontmatter {
    init(yaml: String) {
        let lines = yaml.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || line.first?.isWhitespace == true {
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }

            let key = Self.unquote(String(line[..<colon]).trimmingCharacters(in: .whitespaces))
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if rest.isEmpty {
                // 続くインデント行（またはハイフン始まりの行）をまとめて読む
                var block: [String] = []
                while i < lines.count {
                    let next = lines[i]
                    if next.trimmingCharacters(in: .whitespaces).isEmpty {
                        // 空行は、その先がまだ続きの行なら取り込む
                        let following = lines[i...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        guard let following, following.first?.isWhitespace == true, !block.isEmpty else { break }
                        block.append(next)
                        i += 1
                        continue
                    }
                    guard Self.isContinuation(next) else { break }
                    block.append(next)
                    i += 1
                }
                entries.append(Entry(key: key, value: Self.value(forBlock: block)))
            } else if rest.hasPrefix("["), rest.hasSuffix("]") {
                let inner = rest.dropFirst().dropLast()
                let items = inner.split(separator: ",")
                    .map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
                entries.append(Entry(key: key, value: .list(items)))
            } else {
                entries.append(Entry(key: key, value: .string(Self.unquote(rest))))
            }
        }
    }

    private static func isContinuation(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return line.first?.isWhitespace == true || trimmed.hasPrefix("- ") || trimmed == "-"
    }

    private static func value(forBlock block: [String]) -> Value {
        guard !block.isEmpty else { return .string("") }
        let trimmed = block.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if trimmed.allSatisfy({ $0.hasPrefix("- ") || $0 == "-" }) {
            let items = trimmed
                .map { unquote(String($0.dropFirst()).trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
            return .list(items)
        }
        return .raw(block.joined(separator: "\n"))
    }

    static func unquote(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }
}

// MARK: - 書き出し

extension Frontmatter {
    /// `---` を含まない YAML 本体を返す。
    func serialized() -> String {
        entries.map { entry in
            let key = Self.quoteIfNeeded(entry.key)
            switch entry.value {
            case .string(let s):
                return s.isEmpty ? "\(key):" : "\(key): \(Self.quoteIfNeeded(s))"
            case .list(let items):
                guard !items.isEmpty else { return "\(key): []" }
                return "\(key):\n" + items.map { "  - \(Self.quoteIfNeeded($0))" }.joined(separator: "\n")
            case .raw(let text):
                return "\(key):\n\(text)"
            }
        }
        .joined(separator: "\n")
    }

    static func quoteIfNeeded(_ s: String) -> String {
        let special: Set<Character> = ["[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`", ",", "?", "-"]
        let needsQuote = s.isEmpty
            || s.contains(": ")
            || s.hasSuffix(":")
            || s.contains(" #")
            || s.contains("\n")
            || s.first.map { special.contains($0) || $0.isWhitespace } == true
            || s.last?.isWhitespace == true
        // 負の数（-1 など）は数値のまま残す
        if s.first == "-", Double(s) != nil { return s }
        guard needsQuote else { return s }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
