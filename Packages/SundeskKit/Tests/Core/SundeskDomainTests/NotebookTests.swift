//
//  NotebookTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import Testing

@testable import SundeskDomain

@Suite("Notebook")
struct NotebookTests {
    /// 1x1 の PNG。
    private static let png =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private static let source = """
        {
          "metadata": {"kernelspec": {"language": "python", "name": "python3"}},
          "nbformat": 4,
          "cells": [
            {"cell_type": "markdown", "metadata": {}, "source": ["# 見出し\\n", "本文"]},
            {"cell_type": "code", "execution_count": 3, "metadata": {}, "source": "print(1)",
             "outputs": [
               {"output_type": "stream", "name": "stdout", "text": ["1\\n"]},
               {"output_type": "display_data", "metadata": {},
                "data": {"image/png": "\(png)\\n", "text/plain": ["<Figure>"]}},
               {"output_type": "execute_result", "execution_count": 3, "metadata": {},
                "data": {"text/plain": ["   a\\n0  1"],
                         "text/html": ["<table><thead><tr><th></th><th>a</th></tr></thead>",
                                       "<tbody><tr><th>0</th><td>1 &amp; 2</td></tr></tbody></table>"]}},
               {"output_type": "error", "ename": "ValueError", "evalue": "だめ",
                "traceback": ["\\u001b[31mValueError\\u001b[0m: だめ"]}
             ]},
            {"cell_type": "code", "execution_count": null, "metadata": {}, "source": [], "outputs": []},
            {"cell_type": "raw", "metadata": {}, "source": "生のまま"}
          ]
        }
        """

    @Test("セルの種類と、文字列の配列で書かれたソースを読む")
    func cells() throws {
        let notebook = try #require(Notebook.parse(Self.source))

        #expect(notebook.language == "python")
        #expect(notebook.cells.count == 4)
        #expect(notebook.cells[0] == .markdown("# 見出し\n本文"))
        #expect(notebook.cells[2] == .code(source: "", executionCount: nil, outputs: []))
        #expect(notebook.cells[3] == .raw("生のまま"))
    }

    @Test("出力は、文字、図、表、エラーに分ける")
    func outputs() throws {
        let notebook = try #require(Notebook.parse(Self.source))
        guard case .code(let source, let count, let outputs) = notebook.cells[1] else {
            Issue.record("コードのセルではない")
            return
        }

        #expect(source == "print(1)")
        #expect(count == 3)
        #expect(outputs.count == 4)
        #expect(outputs[0] == .text("1\n"))
        #expect(outputs[1] == .image(try #require(Data(base64Encoded: Self.png))))
        #expect(outputs[2] == .table(rows: [["", "a"], ["0", "1 & 2"]], truncated: false))
        #expect(outputs[3] == .error(name: "ValueError", message: "だめ", traceback: "ValueError: だめ"))
    }

    @Test("ノートブックでない JSON は読まない")
    func rejectsOtherJSON() {
        #expect(Notebook.parse("{\"a\": 1}") == nil)
        #expect(Notebook.parse("壊れた") == nil)
    }

    @Test("長い表は途中までにする")
    func truncatesLongTable() {
        let rows = (0..<300).map { "<tr><td>\($0)</td></tr>" }.joined()
        guard case .table(let parsed, let truncated) = Notebook.table(in: "<table>\(rows)</table>") else {
            Issue.record("表として読めない")
            return
        }
        #expect(parsed.count == Notebook.tableRowLimit)
        #expect(truncated)
    }
}
