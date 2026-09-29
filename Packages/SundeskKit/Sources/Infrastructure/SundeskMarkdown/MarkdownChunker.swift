//
//  MarkdownChunker.swift
//  SundeskMarkdown
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Markdown
import SundeskDomain

/// ノートを見出し（レベル 3 まで）で節に区切る。長い節は段落の切れ目でさらに分ける。
///
/// Domain の `NoteChunking` の実装。RAG の検索と、知識グラフの出現の単位になる。
public struct MarkdownChunker: NoteChunking {
    /// これより長い節は分ける（文字数）。
    private let maxLength: Int

    public init(maxLength: Int = 1200) {
        self.maxLength = maxLength
    }

    public func chunks(for source: String, path: String, title: String) -> [NoteChunk] {
        let body = Frontmatter.split(source).body
        let lineOffset =
            source.split(separator: "\n", omittingEmptySubsequences: false).count
            - body.split(separator: "\n", omittingEmptySubsequences: false).count
        let sections = sections(in: body, title: title)

        var chunks: [NoteChunk] = []
        for section in sections {
            for piece in split(section.lines, startLine: section.startLine) {
                let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let plain = PlainText.extract(from: text)
                guard !plain.isEmpty else { continue }
                chunks.append(
                    NoteChunk(
                        id: "\(path)#\(chunks.count)",
                        notePath: path,
                        noteTitle: title,
                        headingPath: section.path,
                        text: text,
                        plainText: plain,
                        line: piece.line + lineOffset
                    )
                )
            }
        }
        return chunks
    }

    /// 見出し（レベル 3 まで）で節に区切る。見出しの階層はノートのタイトルから始める。
    private func sections(in body: String, title: String) -> [Section] {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let boundaries = Document(parsing: body).children.compactMap { child -> Boundary? in
            guard let heading = child as? Heading, heading.level <= 3, let line = heading.range?.lowerBound.line else {
                return nil
            }
            return Boundary(
                line: line, level: heading.level, text: heading.plainText.trimmingCharacters(in: .whitespaces))
        }

        var sections: [Section] = []
        var stack: [(level: Int, text: String)] = []
        var start = 1
        var currentPath = [title]
        for boundary in boundaries {
            if boundary.line > start {
                sections.append(
                    Section(path: currentPath, startLine: start, lines: lines[(start - 1)..<(boundary.line - 1)]))
            }
            stack.removeAll { $0.level >= boundary.level }
            stack.append((boundary.level, boundary.text))
            // タイトルと同じ H1 は、階層に二重に入れない
            currentPath = [title] + stack.map(\.text).filter { $0 != title }
            start = boundary.line + 1
        }
        if start <= lines.count {
            sections.append(Section(path: currentPath, startLine: start, lines: lines[(start - 1)...]))
        }
        return sections
    }

    /// 見出しの行。
    private struct Boundary {
        let line: Int
        let level: Int
        let text: String
    }

    /// 見出しで区切った節。
    private struct Section {
        let path: [String]
        let startLine: Int
        let lines: ArraySlice<String>
    }

    /// 長い節を、空行（段落の切れ目）で分ける。コードブロックの途中では分けない。
    private func split(_ lines: ArraySlice<String>, startLine: Int) -> [(text: String, line: Int)] {
        var pieces: [(text: String, line: Int)] = []
        var current: [String] = []
        var currentStart = startLine
        var inFence = false
        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            let length = current.reduce(0) { $0 + $1.count + 1 }
            if trimmed.isEmpty, !inFence, length >= maxLength {
                pieces.append((current.joined(separator: "\n"), currentStart))
                current = []
                currentStart = startLine + offset + 1
                continue
            }
            if current.isEmpty && trimmed.isEmpty {
                currentStart = startLine + offset + 1
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { pieces.append((current.joined(separator: "\n"), currentStart)) }
        return pieces
    }
}

/// Markdown から、記法とコードブロックと数式を除いた文字列を取り出す（概念の抽出に使う）。
enum PlainText {
    static func extract(from markdown: String) -> String {
        let protected = Placeholders.protect(markdown)
        var collector = Collector(placeholders: protected)
        collector.visit(Document(parsing: protected.text))
        return collector.text
            .replacing(/[ \t]+/, with: " ")
            .replacing(/\n{2,}/, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Collector: MarkupWalker {
        let placeholders: Placeholders
        var text = ""

        mutating func visitText(_ text: Text) {
            for inline in placeholders.inlines(from: text.string) {
                switch inline {
                case .text(let string): self.text += string
                case .wikilink(_, let label): self.text += label
                default: break  // 数式は除く
                }
            }
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            text += inlineCode.code
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {}

        mutating func visitHTMLBlock(_ html: HTMLBlock) {}

        mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {}

        mutating func visitSoftBreak(_ softBreak: SoftBreak) {
            text += "\n"
        }

        mutating func visitLineBreak(_ lineBreak: LineBreak) {
            text += "\n"
        }

        mutating func visitParagraph(_ paragraph: Paragraph) {
            descendInto(paragraph)
            text += "\n"
        }

        mutating func visitHeading(_ heading: Heading) {
            descendInto(heading)
            text += "\n"
        }

        mutating func visitTableCell(_ tableCell: Table.Cell) {
            descendInto(tableCell)
            text += " "
        }

        mutating func visitTableHead(_ tableHead: Table.Head) {
            descendInto(tableHead)
            text += "\n"
        }

        mutating func visitTableRow(_ tableRow: Table.Row) {
            descendInto(tableRow)
            text += "\n"
        }
    }
}
