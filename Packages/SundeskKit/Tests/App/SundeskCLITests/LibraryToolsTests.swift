//
//  LibraryToolsTests.swift
//  SundeskCLITests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import MCP
import SundeskDomain
import Testing

@testable import SundeskCLI

@Suite("MCP のツール")
struct LibraryToolsTests {
    private func makeTools() async throws -> LibraryTools {
        let metadata = ReferenceMetadata(
            title: "A variational eigenvalue solver", authors: [Creator(family: "Peruzzo", given: "Alberto")],
            issued: PartialDate(year: 2014), doi: "10.1038/ncomms5213")
        let access = try makeAccess(metadata: [.doi("10.1038/ncomms5213"): metadata])
        _ = try await access.library.createCollection(named: "研究", parentID: nil)
        return LibraryTools(access: access)
    }

    private func text(of result: CallTool.Result) -> String {
        guard case .text(let text, _, _) = result.content.first else { return "" }
        return text
    }

    @Test("読むだけのツールと、書き込むツールを、注釈で分ける")
    func annotations() {
        let readOnly = LibraryTools.definitions.filter { $0.annotations.readOnlyHint == true }.map(\.name)

        #expect(readOnly == ["search_references", "get_reference", "list_collections", "get_bibtex"])
    }

    @Test("足した文献を、探して見つけ、コレクションに入れられる")
    func addSearchCollect() async throws {
        let tools = try await makeTools()

        let added = await tools.call("add_reference", arguments: ["source": "10.1038/ncomms5213"])
        let found = await tools.call("search_references", arguments: ["query": "eigenvalue"])
        let collected = await tools.call(
            "add_to_collection", arguments: ["keys": ["peruzzo2014variational"], "collection": "研究"])

        #expect(added.isError == false)
        #expect(text(of: found).contains("\"key\" : \"peruzzo2014variational\""))
        #expect(text(of: collected).contains("\"研究\""))
    }

    @Test("ない文献や、足りない引数は、エラーの結果として返す")
    func errors() async throws {
        let tools = try await makeTools()

        let unknown = await tools.call("get_reference", arguments: ["key": "nobody2000"])
        let missing = await tools.call("add_to_collection", arguments: ["keys": ["peruzzo2014variational"]])

        #expect(unknown.isError == true)
        #expect(text(of: unknown) == "引用キーが「nobody2000」の文献はありません")
        #expect(missing.isError == true)
    }
}
