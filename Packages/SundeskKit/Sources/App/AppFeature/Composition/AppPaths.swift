//
//  AppPaths.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// リポジトリの中の場所。自分専用のアプリで、リポジトリから直接ビルドして使う前提の既定値。
nonisolated enum AppPaths {
    /// リポジトリのルート。このソースファイルの位置から割り出す。
    static func repositoryRoot(sourceFile: String = #filePath) -> URL {
        // .../sundesk/Packages/SundeskKit/Sources/App/AppFeature/Composition/AppPaths.swift
        var url = URL(filePath: sourceFile)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return url
    }

    /// 既定の Vault（モックの SampleVault）。
    static var sampleVault: URL {
        repositoryRoot().appending(path: "SampleVault", directoryHint: .isDirectory)
    }
}
