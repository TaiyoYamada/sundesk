// swift-tools-version: 6.4

import PackageDescription

// sundesk のモジュール構成（docs/architecture.md、docs/adr/0011 を参照）。
//
//   App/            AppFeature … 画面全体の組み立てと DI。全モジュールを知る唯一の場所
//   Features/       機能ごとの Presentation 層（ViewModel と View）。Features どうしは直接依存しない
//   Core/           Domain（どこにも依存しない）、Data（Repository の実装）、DesignSystem
//   Infrastructure/ 外部の技術を包む（Python エンジン、Markdown の解析、コードの色づけ）
//   UI/             機能をまたいで使う画面の部品（閲覧と編集、HTML の表示）

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
        .library(name: "AppFeature", targets: ["AppFeature"])
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory", .upToNextMajor(from: "3.4.1")),
        .package(url: "https://github.com/swiftlang/swift-subprocess", .upToNextMinor(from: "1.0.0")),
        .package(url: "https://github.com/swiftlang/swift-markdown", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/mgriebling/SwiftMath", .upToNextMajor(from: "1.7.3")),
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
                "WorkspaceFeature", "NotesFeature", "EngineFeature", "SettingsFeature",
                "SundeskDomain", "SundeskData", "SundeskDesignSystem",
                "SundeskEngineClient", "SundeskMarkdown",
                .product(name: "FactoryKit", package: "Factory"),
            ],
            path: "Sources/App/AppFeature",
            swiftSettings: uiSettings
        ),

        // MARK: - Features

        .target(
            name: "WorkspaceFeature",
            dependencies: ["NotesFeature", "EngineFeature", "SundeskDomain", "SundeskDesignSystem"],
            path: "Sources/Features/WorkspaceFeature",
            swiftSettings: uiSettings
        ),
        .target(
            name: "NotesFeature",
            dependencies: ["SundeskDomain", "SundeskDesignSystem", "SundeskEditorUI", "SundeskWebView"],
            path: "Sources/Features/NotesFeature",
            swiftSettings: uiSettings
        ),
        .target(
            name: "EngineFeature",
            dependencies: ["SundeskDomain", "SundeskDesignSystem"],
            path: "Sources/Features/EngineFeature",
            swiftSettings: uiSettings
        ),
        .target(
            name: "SettingsFeature",
            dependencies: ["SundeskDomain", "SundeskDesignSystem"],
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
            dependencies: ["SundeskDomain", "SundeskEngineClient"],
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
            name: "SundeskEngineClient",
            dependencies: [.product(name: "Subprocess", package: "swift-subprocess")],
            path: "Sources/Infrastructure/SundeskEngineClient",
            swiftSettings: coreSettings
        ),
        .target(
            name: "SundeskMarkdown",
            dependencies: ["SundeskDomain", .product(name: "Markdown", package: "swift-markdown")],
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
            dependencies: [
                "SundeskMarkdown", "SundeskCodeHighlight", "SundeskDesignSystem",
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
            path: "Sources/UI/SundeskEditorUI",
            swiftSettings: uiSettings
        ),
        .target(
            name: "SundeskWebView",
            path: "Sources/UI/SundeskWebView",
            swiftSettings: uiSettings
        ),

        // MARK: - Tests

        .testTarget(
            name: "AppFeatureTests",
            dependencies: [
                "AppFeature", "WorkspaceFeature", "NotesFeature", "EngineFeature", "SundeskDomain", "SundeskData",
                "SundeskEngineClient",
                .product(name: "FactoryKit", package: "Factory"),
                .product(name: "FactoryTesting", package: "Factory"),
            ],
            path: "Tests/App/AppFeatureTests",
            swiftSettings: uiSettings
        ),
        .testTarget(
            name: "NotesFeatureTests",
            dependencies: ["NotesFeature", "SundeskDomain"],
            path: "Tests/Features/NotesFeatureTests",
            swiftSettings: uiSettings
        ),
        .testTarget(
            name: "WorkspaceFeatureTests",
            dependencies: ["WorkspaceFeature", "NotesFeature", "SundeskDomain"],
            path: "Tests/Features/WorkspaceFeatureTests",
            swiftSettings: uiSettings
        ),
        .testTarget(
            name: "EngineFeatureTests",
            dependencies: ["EngineFeature", "SundeskDomain"],
            path: "Tests/Features/EngineFeatureTests",
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
            dependencies: ["SundeskData", "SundeskDomain", "SundeskEngineClient", "SundeskMarkdown"],
            path: "Tests/Core/SundeskDataTests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "SundeskEngineClientTests",
            dependencies: ["SundeskEngineClient"],
            path: "Tests/Infrastructure/SundeskEngineClientTests",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "SundeskMarkdownTests",
            dependencies: ["SundeskMarkdown", "SundeskDomain"],
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
        .testTarget(
            name: "SundeskWebViewTests",
            dependencies: ["SundeskWebView"],
            path: "Tests/UI/SundeskWebViewTests",
            swiftSettings: uiSettings
        ),
    ]
)
