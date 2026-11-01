//
//  SundeskCommand.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import ArgumentParser

@main
struct SundeskCommand: AsyncParsableCommand {
    /// Configurations/Shared.xcconfig の MARKETING_VERSION と合わせる。
    static let version = "0.3.0"

    static let configuration = CommandConfiguration(
        commandName: "sundesk",
        abstract: "sundesk のライブラリの文献を探し、足す。",
        discussion: """
            アプリと同じライブラリ（~/Library/Application Support/com.taiyou.sundesk/Library）を読み書きする。
            文献は引用キーで、コレクションは名前で指す。同じ名前のコレクションがあるときは「親/子」の形で指す。
            """,
        version: version,
        subcommands: [
            SearchCommand.self, ShowCommand.self, AddCommand.self, CollectCommand.self, CollectionsCommand.self,
            BibCommand.self, MCPCommand.self,
        ]
    )
}
