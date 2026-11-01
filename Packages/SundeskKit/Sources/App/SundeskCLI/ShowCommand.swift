//
//  ShowCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "1 件の文献を、要旨、メモ、要約まで含めて JSON で出す。"
    )

    @Argument(help: "引用キー。")
    var key: String

    func run() async throws {
        print(try JSONOutput.string(try await LibraryAccess.open().reference(key: key)))
    }
}
