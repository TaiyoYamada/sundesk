//
//  LibraryTools.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import MCP

/// MCP サーバーのツール。中身は CLI の命令と同じ（LibraryAccess）。消す、書誌情報を直すツールは出さない。
struct LibraryTools {
    let access: LibraryAccess

    static let definitions: [Tool] = [
        Tool(
            name: "search_references",
            description: "文献を探す。語をすべて、題名、著者、年、掲載先、タグ、引用キーのどこかに含むものを、新しく足した順に返す。",
            inputSchema: schema(
                properties: [
                    "query": text("空白で区切った語。空ならすべて。"),
                    "collection": text("このコレクション（中のコレクションも含む）から探す。"),
                    "tag": text("このタグの付いた文献から探す。"),
                    "limit": ["type": "integer", "description": "返す件数の上限。既定は 20。"],
                ],
                required: []),
            annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(
            name: "get_reference",
            description: "1 件の文献を、要旨、メモ（Markdown）、要約、PDF のパスまで含めて返す。",
            inputSchema: schema(properties: ["key": text("引用キー。")], required: ["key"]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(
            name: "list_collections",
            description: "コレクション（「親/子」の形の名前）と、その中の文献の数を返す。",
            inputSchema: schema(properties: [:], required: []),
            annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(
            name: "get_bibtex",
            description: "文献の BibTeX を返す。",
            inputSchema: schema(properties: ["keys": keys], required: ["keys"]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(
            name: "add_reference",
            description: """
                DOI、arXiv の ID、ISBN、または Mac の PDF のパスから文献を足し、足した文献を返す。
                同じ文献がすでにあれば、足さずにそれを返す。arXiv の論文は PDF も取ってくる。
                """,
            inputSchema: schema(
                properties: [
                    "source": text("DOI、arXiv の ID、ISBN（URL でもよい）、または PDF の絶対パス。"),
                    "collection": text("足した文献を入れるコレクション。"),
                ],
                required: ["source"]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true)),
        Tool(
            name: "add_to_collection",
            description: "文献をコレクションに入れる。入っていたコレクションからは外さない。",
            inputSchema: schema(
                properties: ["keys": keys, "collection": text("入れるコレクション。")],
                required: ["keys", "collection"]),
            annotations: .init(
                readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
    ]

    func call(_ name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            let output: String
            switch name {
            case "search_references":
                output = try JSONOutput.string(
                    try await access.search(
                        arguments["query"]?.stringValue ?? "", collection: arguments["collection"]?.stringValue,
                        tag: arguments["tag"]?.stringValue, limit: arguments["limit"]?.intValue ?? 20))
            case "get_reference":
                output = try JSONOutput.string(try await access.reference(key: try string("key", in: arguments)))
            case "list_collections":
                output = try JSONOutput.string(try await access.collections())
            case "get_bibtex":
                output = try await access.bibTeX(keys: try strings("keys", in: arguments))
            case "add_reference":
                output = try JSONOutput.string(
                    try await access.add(
                        try string("source", in: arguments), collection: arguments["collection"]?.stringValue))
            case "add_to_collection":
                output = try JSONOutput.string(
                    try await access.collect(
                        keys: try strings("keys", in: arguments), into: try string("collection", in: arguments)))
            default:
                throw MCPError.methodNotFound("ツール \(name) はありません")
            }
            return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)], isError: false)
        } catch {
            return CallTool.Result(
                content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
        }
    }

    private func string(_ name: String, in arguments: [String: Value]) throws -> String {
        guard let value = arguments[name]?.stringValue else { throw MCPError.invalidParams("\(name) がありません") }
        return value
    }

    private func strings(_ name: String, in arguments: [String: Value]) throws -> [String] {
        guard let values = arguments[name]?.arrayValue?.compactMap(\.stringValue), !values.isEmpty else {
            throw MCPError.invalidParams("\(name) がありません")
        }
        return values
    }

    // MARK: - 入力の JSON Schema

    private static let keys: Value = ["type": "array", "items": ["type": "string"], "description": "引用キー。"]

    private static func text(_ description: String) -> Value {
        ["type": "string", "description": .string(description)]
    }

    private static func schema(properties: [String: Value], required: [String]) -> Value {
        ["type": "object", "properties": .object(properties), "required": .array(required.map(Value.string))]
    }
}
