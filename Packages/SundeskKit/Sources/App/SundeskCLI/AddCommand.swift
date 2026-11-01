//
//  AddCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "DOI、arXiv の ID、ISBN、または PDF から文献を足す。",
        discussion: "同じ文献がすでにあれば、足さずにそれを出す。arXiv の論文は PDF も取ってくる。"
    )

    @Argument(help: "DOI、arXiv の ID、ISBN（URL でもよい）、または PDF のパス。")
    var source: String

    @Option(help: "足した文献を入れるコレクション。")
    var collection: String?

    @Flag(help: "JSON で出す。")
    var json = false

    func run() async throws {
        let item = try await LibraryAccess.open().add(source, collection: collection)
        print(json ? try JSONOutput.string(item) : item.line)
    }
}
