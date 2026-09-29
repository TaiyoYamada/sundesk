//
//  AppPaths.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData

/// リポジトリの中の場所。自分専用のアプリで、リポジトリから直接ビルドして使う前提の既定値。
nonisolated enum AppPaths {
    /// このソースファイルの場所（引数の既定値に `#filePath` を書くと、呼び出した側の場所になる）。
    private static let sourceFile = #filePath

    /// リポジトリのルート。このソースファイルの位置から割り出す。
    static func repositoryRoot(sourceFile: String = AppPaths.sourceFile) -> URL {
        // .../sundesk/Packages/SundeskKit/Sources/App/AppFeature/Composition/AppPaths.swift
        var url = URL(filePath: sourceFile)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return url
    }

    /// 研究向けの見本のライブラリ（開発とテストで使う）。
    static var sampleLibrary: URL {
        repositoryRoot().appending(path: "SampleLibrary", directoryHint: .isDirectory)
    }

    /// 本物の研究ライブラリ（アプリのデータフォルダの中）。
    static var library: URL {
        (try? AppDataDirectory.url("Library"))
            ?? FileManager.default.temporaryDirectory.appending(path: "sundesk-library", directoryHint: .isDirectory)
    }
}
