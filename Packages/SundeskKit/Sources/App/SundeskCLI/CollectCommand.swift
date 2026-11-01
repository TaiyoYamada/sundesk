//
//  CollectCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

struct CollectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collect",
        abstract: "文献をコレクションに入れる。入っていたコレクションからは外さない。"
    )

    @Argument(help: "引用キー。")
    var keys: [String]

    @Option(name: .customLong("into"), help: "入れるコレクション。")
    var collection: String

    func run() async throws {
        for item in try await LibraryAccess.open().collect(keys: keys, into: collection) { print(item.line) }
    }
}
