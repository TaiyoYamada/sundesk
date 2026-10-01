//
//  Notebook.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// Jupyter のノートブック（`.ipynb`）。セルと、保存されている出力。
public struct Notebook: Equatable, Sendable {
    public enum Cell: Equatable, Sendable {
        case markdown(String)
        case code(source: String, executionCount: Int?, outputs: [Output])
        case raw(String)
    }

    public enum Output: Equatable, Sendable {
        /// 標準出力や、式の値の文字表現。
        case text(String)
        /// 図（PNG や JPEG のバイト列）。
        case image(Data)
        /// 表（pandas の DataFrame など、HTML の表から読んだもの）。先頭の行が見出し。
        case table(rows: [[String]], truncated: Bool)
        case error(name: String, message: String, traceback: String)
    }

    /// コードの言語（色づけに使う）。
    public let language: String
    public let cells: [Cell]

    public init(language: String, cells: [Cell]) {
        self.language = language
        self.cells = cells
    }

    /// 1 つの出力として見せる文字の長さの上限（大きなログで画面が重くならないように）。
    public static let textLimit = 20_000

    /// `.ipynb` の JSON を読む。形が違えば nil。
    public static func parse(_ source: String) -> Notebook? {
        guard let data = source.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawCells = root["cells"] as? [[String: Any]]
        else { return nil }
        let metadata = root["metadata"] as? [String: Any]
        let language =
            ((metadata?["kernelspec"] as? [String: Any])?["language"] as? String)
            ?? ((metadata?["language_info"] as? [String: Any])?["name"] as? String) ?? "python"
        let cells = rawCells.map { cell -> Cell in
            let text = joined(cell["source"])
            switch cell["cell_type"] as? String {
            case "markdown":
                return .markdown(text)
            case "code":
                let outputs = (cell["outputs"] as? [[String: Any]] ?? []).compactMap(output)
                return .code(source: text, executionCount: cell["execution_count"] as? Int, outputs: outputs)
            default:
                return .raw(text)
            }
        }
        return Notebook(language: language.lowercased(), cells: cells)
    }

    private static func output(_ raw: [String: Any]) -> Output? {
        switch raw["output_type"] as? String {
        case "stream":
            return .text(limited(joined(raw["text"])))
        case "error":
            let traceback = (raw["traceback"] as? [String] ?? []).joined(separator: "\n")
            return .error(
                name: raw["ename"] as? String ?? "Error", message: raw["evalue"] as? String ?? "",
                traceback: limited(stripANSI(traceback)))
        case "execute_result", "display_data":
            guard let data = raw["data"] as? [String: Any] else { return nil }
            for type in ["image/png", "image/jpeg"] {
                let base64 = joined(data[type]).filter { !$0.isWhitespace }
                if !base64.isEmpty, let bytes = Data(base64Encoded: base64) { return .image(bytes) }
            }
            // pandas の表は HTML の表のほうが読みやすい。それ以外は文字の表現を使う
            let html = joined(data["text/html"])
            if let table = table(in: html) { return table }
            let text = joined(data["text/plain"])
            if !text.isEmpty { return .text(limited(text)) }
            if !html.isEmpty { return .text(limited(plainText(html))) }
            return nil
        default:
            return nil
        }
    }

    /// ノートブックの文字は、文字列か文字列の配列で入っている。
    private static func joined(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let lines = value as? [String] { return lines.joined() }
        return ""
    }

    private static func limited(_ text: String) -> String {
        text.count > textLimit ? String(text.prefix(textLimit)) + "\n…（長いので省略しました）" : text
    }

    /// 表として見せる行の数の上限。
    public static let tableRowLimit = 200

    /// HTML の最初の `<table>` を、行とセルの文字に分ける。
    static func table(in html: String) -> Output? {
        guard let table = html.firstMatch(of: /(?is)<table\b.*?<\/table>/)?.output else { return nil }
        var rows: [[String]] = []
        var truncated = false
        for row in table.matches(of: /(?is)<tr\b[^>]*>(.*?)<\/tr>/) {
            let cells = row.output.1.matches(of: /(?is)<t[hd]\b[^>]*>(.*?)<\/t[hd]>/).map {
                plainText(String($0.output.1))
            }
            guard !cells.isEmpty else { continue }
            if rows.count >= tableRowLimit {
                truncated = true
                break
            }
            rows.append(cells)
        }
        return rows.isEmpty ? nil : .table(rows: rows, truncated: truncated)
    }

    /// タグを除き、よく使う文字参照を戻す。
    static func plainText(_ html: String) -> String {
        html.replacing(/(?i)<br\s*\/?>/, with: "\n")
            .replacing(/<[^>]+>/, with: "")
            .replacing("&nbsp;", with: " ").replacing("&lt;", with: "<").replacing("&gt;", with: ">")
            .replacing("&quot;", with: "\"").replacing("&#39;", with: "'").replacing("&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 端末の色づけの記号（`ESC[31m` など）を除く。
    static func stripANSI(_ text: String) -> String {
        text.replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }
}
