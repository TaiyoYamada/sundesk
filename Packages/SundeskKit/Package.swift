// swift-tools-version: 6.4

import PackageDescription

// 依存の向きは docs/architecture.md の「層」を参照。
// 内側の層（Domain）から外側の層を import できないように、モジュールを分けている。

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "SundeskKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "SundeskDomain", targets: ["SundeskDomain"]),
        .library(name: "SundeskEngine", targets: ["SundeskEngine"]),
        .library(name: "SundeskData", targets: ["SundeskData"]),
        .library(name: "SundeskPresentation", targets: ["SundeskPresentation"]),
        .library(name: "SundeskComposition", targets: ["SundeskComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory", .upToNextMajor(from: "3.4.1")),
        .package(url: "https://github.com/swiftlang/swift-subprocess", .upToNextMinor(from: "1.0.0")),
    ],
    targets: [
        // Domain: Entity、UseCase、Repository の protocol。どこにも依存しない。
        .target(
            name: "SundeskDomain",
            swiftSettings: swiftSettings
        ),
        // Infrastructure: AI エンジン（Python）のプロセス管理と通信。アプリの型は知らない。
        .target(
            name: "SundeskEngine",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess")
            ],
            swiftSettings: swiftSettings
        ),
        // Data: Repository の実装。Domain の protocol を、Infrastructure を使って満たす。
        .target(
            name: "SundeskData",
            dependencies: ["SundeskDomain", "SundeskEngine"],
            swiftSettings: swiftSettings
        ),
        // Presentation: ViewModel。Domain の UseCase だけを知る。
        .target(
            name: "SundeskPresentation",
            dependencies: ["SundeskDomain"],
            swiftSettings: swiftSettings
        ),
        // Composition Root: Factory のコンテナにすべてを登録する。全モジュールを知る唯一の場所。
        .target(
            name: "SundeskComposition",
            dependencies: [
                "SundeskDomain",
                "SundeskEngine",
                "SundeskData",
                "SundeskPresentation",
                .product(name: "FactoryKit", package: "Factory"),
            ],
            swiftSettings: swiftSettings
        ),

        .testTarget(
            name: "SundeskDomainTests",
            dependencies: ["SundeskDomain"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SundeskEngineTests",
            dependencies: ["SundeskEngine"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SundeskDataTests",
            dependencies: ["SundeskData", "SundeskDomain", "SundeskEngine"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SundeskPresentationTests",
            dependencies: ["SundeskPresentation", "SundeskDomain"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SundeskCompositionTests",
            dependencies: [
                "SundeskComposition",
                "SundeskEngine",
                "SundeskPresentation",
                .product(name: "FactoryTesting", package: "Factory"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
