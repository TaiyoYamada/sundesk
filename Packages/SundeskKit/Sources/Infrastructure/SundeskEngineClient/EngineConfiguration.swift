//
//  EngineConfiguration.swift
//  SundeskEngineClient
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
    /// 作ったモデル（量子化、蒸留など）を置くフォルダ。エンジンはここにあるモデルも一覧に出す。
    public var modelsDirectory: URL?

    public init(
        engineDirectory: URL, uvExecutable: URL, startupTimeout: Duration = .seconds(600), modelsDirectory: URL? = nil
    ) {
        self.engineDirectory = engineDirectory
        self.uvExecutable = uvExecutable
        self.startupTimeout = startupTimeout
        self.modelsDirectory = modelsDirectory
    }
}

/// uv やエンジンのフォルダを探す。
public enum EngineLocator {
    /// このソースファイルの場所。
    public static let sourceFile = #filePath

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
    ///
    /// 引数の既定値に `#filePath` を直接書くと、呼び出した側のファイルの場所になってしまう。
    /// このファイルの場所は ``sourceFile`` に取っておく。
    public static func defaultEngineDirectory(sourceFile: String = EngineLocator.sourceFile) -> URL {
        // .../sundesk/Packages/SundeskKit/Sources/Infrastructure/SundeskEngineClient/EngineConfiguration.swift
        URL(filePath: sourceFile)
            .deletingLastPathComponent()  // SundeskEngineClient
            .deletingLastPathComponent()  // Infrastructure
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // SundeskKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // sundesk（リポジトリのルート）
            .appending(path: "engine", directoryHint: .isDirectory)
    }
}
