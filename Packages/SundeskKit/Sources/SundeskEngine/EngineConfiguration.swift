//
//  EngineConfiguration.swift
//  SundeskEngine
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// エンジンを起動するための設定。
public struct EngineConfiguration: Sendable, Equatable {
    /// `engine/`（pyproject.toml のあるフォルダ）の場所。
    public var engineDirectory: URL
    /// uv の実行ファイルの場所。Python の環境づくりと起動を uv に任せる。
    public var uvExecutable: URL
    /// 起動してから応答が返るまで待つ時間。初回は依存関係の取得で時間がかかる。
    public var startupTimeout: Duration

    public init(engineDirectory: URL, uvExecutable: URL, startupTimeout: Duration = .seconds(180)) {
        self.engineDirectory = engineDirectory
        self.uvExecutable = uvExecutable
        self.startupTimeout = startupTimeout
    }
}

/// uv やエンジンのフォルダを探す。
public enum EngineLocator {
    /// uv を探す。
    ///
    /// GUI アプリは PATH を引き継がないので、よく置かれる場所を先に調べ、
    /// 見つからなければ PATH を調べる（ターミナルや CI から起動したとき）。
    public static func findUV(
        wellKnownLocations: [URL] = wellKnownUVLocations,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let onPath = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "uv") }
        return (wellKnownLocations + onPath).first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Homebrew（Apple シリコンと Intel）と、uv の公式インストーラが置く場所。
    public static var wellKnownUVLocations: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(filePath: "/opt/homebrew/bin/uv"),
            URL(filePath: "/usr/local/bin/uv"),
            home.appending(path: ".local/bin/uv"),
            home.appending(path: ".cargo/bin/uv"),
        ]
    }

    /// このソースファイルの位置からリポジトリの `engine/` を割り出す。
    ///
    /// 自分専用のアプリで、リポジトリから直接ビルドして使う前提の既定値。
    /// 設定画面で別の場所に変えられる。
    public static func defaultEngineDirectory(sourceFile: String = #filePath) -> URL {
        // .../sundesk/Packages/SundeskKit/Sources/SundeskEngine/EngineConfiguration.swift
        URL(filePath: sourceFile)
            .deletingLastPathComponent()  // SundeskEngine
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // SundeskKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // sundesk（リポジトリのルート）
            .appending(path: "engine", directoryHint: .isDirectory)
    }
}
