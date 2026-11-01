//
//  CommandError.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

enum CommandError: LocalizedError {
    case unknownReference(String)
    case unknownCollection(String)
    /// 同じ名前のコレクションが 2 つ以上ある。「親/子」の形で選んでもらう。
    case ambiguousCollection(String, [String])

    var errorDescription: String? {
        switch self {
        case .unknownReference(let key):
            "引用キーが「\(key)」の文献はありません"
        case .unknownCollection(let name):
            "「\(name)」というコレクションはありません"
        case .ambiguousCollection(let name, let paths):
            "「\(name)」というコレクションが \(paths.count) つあります。次のどれかで指定してください: "
                + paths.joined(separator: "、")
        }
    }
}
