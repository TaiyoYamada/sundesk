//
//  BibCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

struct BibCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bib",
        abstract: "文献の BibTeX を出す。"
    )

    @Argument(help: "引用キー。")
    var keys: [String]

    func run() async throws {
        print(try await LibraryAccess.open().bibTeX(keys: keys))
    }
}
