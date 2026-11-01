//
//  MCPCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser
import MCP

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP サーバーとして、標準入出力で待つ。",
        discussion: "MCP のクライアント（Claude Code、JobNeko の agentd など）が、このコマンドを子のプロセスとして起動する。"
    )

    func run() async throws {
        let tools = LibraryTools(access: try LibraryAccess.open())
        let server = Server(
            name: "sundesk", version: SundeskCommand.version,
            instructions: """
                sundesk は、利用者の論文と本の文献管理アプリ。文献は引用キー（例: peruzzo2014variational）で、
                コレクションは名前（同じ名前があれば「親/子」の形）で指す。足す前に search_references で、すでにあるかを確かめる。
                """,
            capabilities: .init(tools: .init(listChanged: false)))
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: LibraryTools.definitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await tools.call(params.name, arguments: params.arguments ?? [:])
        }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
