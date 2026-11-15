//
//  CreateCollectionCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/15.
//

import ArgumentParser

struct CreateCollectionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-collection",
        abstract: "コレクションを作る。「親/子」の形で指し、ない親も作る。"
    )

    @Argument(help: "作るコレクション。")
    var path: String

    func run() async throws {
        print(try await LibraryAccess.open().createCollection(path))
    }
}
