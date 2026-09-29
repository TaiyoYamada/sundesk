//
//  LinkResolverTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import Testing

@Suite("VaultPath")
struct VaultPathTests {
    @Test(
        "相対パスを Vault のルートからのパスに直す",
        arguments: [
            ("量子計算/量子ビット.md", "../資料/図.png", "資料/図.png"),
            ("量子計算/量子ビット.md", "./量子ゲート.md", "量子計算/量子ゲート.md"),
            ("ホーム.md", "数学/ベクトル.md", "数学/ベクトル.md"),
            ("ホーム.md", "../外.md", nil),
            ("a/b.md", "c%20d.md#見出し", "a/c d.md"),
            ("a/b.md", "/ルート.md", "ルート.md"),
        ]
    )
    func resolvesRelativePaths(note: String, relative: String, expected: String?) {
        #expect(VaultPath.resolve(relative, from: note) == expected)
    }
}

@Suite("LinkResolver")
struct LinkResolverTests {
    private let resolver = LinkResolver(paths: [
        "ホーム.md",
        "数学/線形代数/ベクトル.md",
        "数学/線形代数/固有値・固有状態.md",
        "量子計算/量子ゲート.md",
        "量子計算/実験レポート_VQE.html",
        "研究ログ/ベクトル.md",
    ])

    @Test(
        "Obsidian と同じ順でリンク先を探す",
        arguments: [
            ("数学/線形代数/ベクトル", "数学/線形代数/ベクトル.md"),
            ("線形代数/ベクトル", "数学/線形代数/ベクトル.md"),
            ("量子ゲート", "量子計算/量子ゲート.md"),
            ("固有値・固有状態#測定", "数学/線形代数/固有値・固有状態.md"),
            ("実験レポート_VQE.html", "量子計算/実験レポート_VQE.html"),
            ("ホーム", "ホーム.md"),
            ("/ホーム.md", "ホーム.md"),
            ("存在しない", nil),
        ]
    )
    func resolves(target: String, expected: String?) {
        #expect(resolver.resolve(target) == expected)
    }

    @Test("同じ名前が複数あれば、浅い場所のものを選ぶ")
    func prefersShallowerPath() {
        #expect(resolver.resolve("ベクトル") == "研究ログ/ベクトル.md")
    }

    @Test("正確なパスの指定では、名前での推測をしない")
    func exactDoesNotGuess() {
        #expect(resolver.resolve("量子ゲート.md", exact: true) == nil)
        #expect(resolver.resolve("量子計算/量子ゲート.md", exact: true) == "量子計算/量子ゲート.md")
    }
}
