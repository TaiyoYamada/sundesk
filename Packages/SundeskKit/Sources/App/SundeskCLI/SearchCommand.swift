//
//  SearchCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "文献を探す。語をすべて、題名、著者、年、掲載先、タグ、引用キーのどこかに含むものを、新しく足した順に出す。"
    )

    @Argument(help: "探す語。空白で区切る。なければすべて。")
    var words: [String] = []

    @Option(help: "このコレクション（中のコレクションも含む）から探す。")
    var collection: String?

    @Option(help: "このタグの付いた文献から探す。")
    var tag: String?

    @Option(help: "出す件数の上限。")
    var limit: Int?

    @Flag(help: "JSON で出す。")
    var json = false

    func run() async throws {
        let items = try await LibraryAccess.open().search(
            words.joined(separator: " "), collection: collection, tag: tag, limit: limit)
        if json {
            print(try JSONOutput.string(items))
        } else {
            for item in items { print(item.line) }
        }
    }
}
