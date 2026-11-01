// swift-tools-version: 6.4

import PackageDescription

// sundesk のモジュール構成（docs/architecture.md、docs/adr/0011 を参照）。
//
//   App/            AppFeature … 画面全体の組み立てと DI。SundeskCLI … CLI と MCP サーバー（画面を持たない入口）
//   Features/       機能ごとの Presentation 層（ViewModel と View）。Features どうしは直接依存しない
//   Core/           Domain（どこにも依存しない）、Data（Repository の実装）、DesignSystem
//   Infrastructure/ 外部の技術を包む（Markdown の解析、コードの色づけ）
//   UI/             機能をまたいで使う画面の部品（Markdown のメモのエディタ）

/// Domain、Data、Infrastructure: 既定で nonisolated（Swift 6 の標準）。
let coreSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

/// 画面を扱うモジュール: 既定で MainActor。
let uiSettings: [SwiftSetting] = coreSettings + [.defaultIsolation(MainActor.self)]

/// コードの色づけに使う tree-sitter の文法（言語ごとのパッケージ）。
let grammars: [(product: String, package: String)] = [
    ("TreeSitterSwift", "tree-sitter-swift"),
    ("TreeSitterPython", "tree-sitter-python"),
    ("TreeSitterJavaScript", "tree-sitter-javascript"),
    ("TreeSitterTypeScript", "tree-sitter-typescript"),
    ("TreeSitterJSON", "tree-sitter-json"),
    ("TreeSitterHTML", "tree-sitter-html"),
    ("TreeSitterCSS", "tree-sitter-css"),
    ("TreeSitterBash", "tree-sitter-bash"),
    ("TreeSitterRust", "tree-sitter-rust"),
    ("TreeSitterGo", "tree-sitter-go"),
    ("TreeSitterC", "tree-sitter-c"),
    ("TreeSitterCPP", "tree-sitter-cpp"),
    ("TreeSitterJava", "tree-sitter-java"),
    ("TreeSitterYAML", "tree-sitter-yaml"),
]

let package = Package(
    name: "SundeskKit",
    platforms: [.macOS(.v27)],
    products: [
        // アプリのターゲットが使うのは AppFeature だけ
        .library(name: "AppFeature", targets: ["AppFeature"]),
        // ターミナルと MCP のクライアントから使う。入れるときに sundesk という名前にする（Makefile の install-cli）
        .executable(name: "sundesk-cli", targets: ["SundeskCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory", .upToNextMajor(from: "3.4.1")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.8.2")),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", .upToNextMinor(from: "0.12.1")),
        .package(url: "https://github.com/swiftlang/swift-markdown", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", .upToNextMinor(from: "0.10.0")),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.3-with-generated-files"),
        // 次の 4 つは、Sources/Infrastructure/TreeSitterScanners の scanner.c と同じバージョンに固定する
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", .upToNextMinor(from: "0.23.2")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", .upToNextMinor(from: "0.24.8")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", .upToNextMinor(from: "0.23.2")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", .upToNextMinor(from: "0.25.1")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", .upToNextMinor(from: "0.24.2")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", .upToNextMinor(from: "0.25.0")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c", .upToNextMinor(from: "0.24.2")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", .upToNextMinor(from: "0.23.4")),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", .upToNextMinor(from: "0.23.5")),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-yaml", exact: "0.7.2"),
    ],
    targets: [
        // MARK: - App

        .target(
            name: "AppFeature",
            dependencies: [
                "LibraryFeature", "SettingsFeature", "SundeskDomain", "SundeskData", "SundeskDesignSystem",
                .product(name: "FactoryKit", package: "Factory"),
            ],
            path: "Sources/App/AppFeature",
            swiftSettings: uiSettings
        ),
        .executableTarget(
            name: "SundeskCLI",
            dependencies: [
                "SundeskDomain", "SundeskData",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/App/SundeskCLI",
            swiftSettings: coreSettings
        ),

        // MARK: - Features

        .target(
            name: "LibraryFeature",
            dependencies: ["SundeskDomain", "SundeskDesignSystem", "SundeskEditorUI"],
            path: "Sources/Features/LibraryFeature",
            swiftSettings: uiSettings
        ),
        .target(
            name: "SettingsFeature",
            dependencies: ["SundeskDesignSystem"],
            path: "Sources/Features/SettingsFeature",
            swiftSettings: uiSettings
        ),

        // MARK: - Core

        .target(
            name: "SundeskDomain",
            path: "Sources/Core/SundeskDomain",
            swiftSettings: coreSettings
        ),
        .target(
            name: "SundeskData",
            dependencies: ["SundeskDomain"],
            path: "Sources/Core/SundeskData",
            swiftSettings: coreSettings
        ),
        .target(
            name: "SundeskDesignSystem",
            path: "Sources/Core/SundeskDesignSystem",
            swiftSettings: uiSettings
        ),

        // MARK: - Infrastructure

        .target(
            name: "SundeskMarkdown",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/Infrastructure/SundeskMarkdown",
            swiftSettings: coreSettings
        ),
        .target(
            name: "SundeskCodeHighlight",
            dependencies: ["TreeSitterScanners", .product(name: "SwiftTreeSitter", package: "swift-tree-sitter")]
                + grammars.map { .product(name: $0.product, package: $0.package) },
            path: "Sources/Infrastructure/SundeskCodeHighlight",
            swiftSettings: coreSettings
        ),

        // 文法パッケージからビルドが漏れる scanner.c を補う（README.md を参照）
        .target(
            name: "TreeSitterScanners",
            path: "Sources/Infrastructure/TreeSitterScanners",
            exclude: ["README.md", "yaml/schema.core.c"]
                + ["css", "javascript", "python", "yaml"].map { "\($0)/LICENSE" },
            cSettings: [.unsafeFlags(["-w"])]
        ),

        // MARK: - UI

        .target(
            name: "SundeskEditorUI",
            dependencies: ["SundeskMarkdown", "SundeskCodeHighlight", "SundeskDesignSystem"],
            path: "Sources/UI/SundeskEditorUI",
            swiftSettings: uiSettings
        ),

        // MARK: - Tests

        .testTarget(
            name: "SundeskCLITests",
            dependencies: ["SundeskCLI", "SundeskDomain", "SundeskData", .product(name: "MCP", package: "swift-sdk")],
            path: "Tests/App/SundeskCLITests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "LibraryFeatureTests",
            dependencies: ["LibraryFeature", "SundeskDomain", "SundeskData"],
            path: "Tests/Features/LibraryFeatureTests",
            swiftSettings: uiSettings
        ),
        .testTarget(
            name: "SundeskDomainTests",
            dependencies: ["SundeskDomain"],
            path: "Tests/Core/SundeskDomainTests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "SundeskDataTests",
            dependencies: ["SundeskData", "SundeskDomain"],
            path: "Tests/Core/SundeskDataTests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "SundeskMarkdownTests",
            dependencies: ["SundeskMarkdown"],
            path: "Tests/Infrastructure/SundeskMarkdownTests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "SundeskCodeHighlightTests",
            dependencies: ["SundeskCodeHighlight"],
            path: "Tests/Infrastructure/SundeskCodeHighlightTests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "SundeskEditorUITests",
            dependencies: ["SundeskEditorUI", "SundeskMarkdown", "SundeskCodeHighlight"],
            path: "Tests/UI/SundeskEditorUITests",
            swiftSettings: uiSettings
        ),
    ]
)
