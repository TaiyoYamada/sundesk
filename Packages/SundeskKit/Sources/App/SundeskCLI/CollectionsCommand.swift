//
//  CollectionsCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

struct CollectionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collections",
        abstract: "コレクションと、その中の文献の数を出す。"
    )

    @Flag(help: "JSON で出す。")
    var json = false

    func run() async throws {
        let items = try await LibraryAccess.open().collections()
        if json {
            print(try JSONOutput.string(items))
        } else {
            for item in items { print("\(item.path)\t\(item.count)") }
        }
    }
}
