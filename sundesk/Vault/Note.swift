import Foundation

/// Vault 内の 1 つの Markdown ファイル。
///
/// ファイルの中身（`content`）が唯一の正で、フロントマター・タグ・リンクは
/// そこから導出する。中身を差し替えるときは `setContent(_:)` を通す。
nonisolated struct Note: Identifiable, Hashable, Sendable {
    /// Vault ルートからの相対パス（例: `Books/Dune.md`）。
    let id: String
    private(set) var content: String
    var modified: Date

    private(set) var frontmatter: Frontmatter
    private(set) var body: String
    private(set) var tags: [String]
    /// `[[...]]` のリンク先（見出しやエイリアスを除いたもの）。
    private(set) var links: [String]

    init(id: String, content: String, modified: Date = .now) {
        self.id = id
        self.content = content
        self.modified = modified
        (frontmatter, body, tags, links) = Self.parse(content)
    }

    mutating func setContent(_ newContent: String) {
        content = newContent
        (frontmatter, body, tags, links) = Self.parse(newContent)
    }

    /// ファイル名から拡張子を除いたもの。Obsidian と同じくこれがノートの名前になる。
    var title: String {
        ((id as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// 所属フォルダの相対パス。ルート直下なら空文字。
    var folder: String {
        (id as NSString).deletingLastPathComponent
    }

    /// 構造化データとしての種類（フロントマターの `type`）。
    var type: String? {
        frontmatter.string("type")?.trimmingCharacters(in: .whitespaces)
    }

    /// 一覧に出す短い抜粋。見出し記号などを落とした本文の先頭。
    var excerpt: String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#>-*+ "))
            if !text.isEmpty, !text.hasPrefix("```") { return String(text.prefix(140)) }
        }
        return ""
    }

    private static func parse(_ content: String) -> (Frontmatter, String, [String], [String]) {
        let (yaml, body) = Frontmatter.split(content)
        let frontmatter = yaml.map(Frontmatter.init(yaml:)) ?? Frontmatter()

        var tags = (frontmatter.list("tags") + frontmatter.list("tag"))
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
        tags += MarkdownScanner.tags(in: body)

        var seen = Set<String>()
        tags = tags.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        return (frontmatter, body, tags, MarkdownScanner.wikilinks(in: body))
    }
}

/// 本文からリンクやタグを拾う。コードブロックとインラインコードの中は対象外。
nonisolated enum MarkdownScanner {
    private static let wikilinkPattern = try! NSRegularExpression(
        pattern: #"!?\[\[([^\]\|#\^\n]+)(?:[#\^][^\]\|\n]*)?(?:\|([^\]\n]*))?\]\]"#
    )
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_&/#])#([\p{L}\p{N}_/\-]*[\p{L}_/\-][\p{L}\p{N}_/\-]*)"#
    )
    private static let inlineCodePattern = try! NSRegularExpression(pattern: "`[^`\n]*`")

    static func wikilinks(in body: String) -> [String] {
        let text = stripCode(body)
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return wikilinkPattern.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            let target = text[r].trimmingCharacters(in: .whitespaces)
            return seen.insert(target.lowercased()).inserted ? target : nil
        }
    }

    static func tags(in body: String) -> [String] {
        let text = stripCode(body)
        let range = NSRange(text.startIndex..., in: text)
        return tagPattern.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// フェンスで囲まれたコードブロックとインラインコードを取り除く。
    static func stripCode(_ body: String) -> String {
        var result: [Substring] = []
        var inFence = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if !inFence { result.append(line) }
        }
        let joined = result.joined(separator: "\n")
        return inlineCodePattern.stringByReplacingMatches(
            in: joined, range: NSRange(joined.startIndex..., in: joined), withTemplate: ""
        )
    }
}
