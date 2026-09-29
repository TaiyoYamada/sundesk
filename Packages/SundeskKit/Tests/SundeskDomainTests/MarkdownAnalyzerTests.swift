//
//  MarkdownAnalyzerTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import Testing

@Suite("MarkdownAnalyzer")
struct MarkdownAnalyzerTests {
    @Test("フロントマターのプロパティを読む")
    func readsFrontmatterProperties() {
        let analysis = MarkdownAnalyzer.analyze(
            """
            ---
            title: "固有値・固有状態"
            status: 執筆済
            tags: [数学, 線形代数]
            aliases:
              - eigenvalue
              - 固有値
            ---
            本文
            """,
            path: "a.md"
        )

        #expect(analysis.title == "固有値・固有状態")
        #expect(
            analysis.properties == [
                NoteProperty(key: "title", value: .text("固有値・固有状態")),
                NoteProperty(key: "status", value: .text("執筆済")),
                NoteProperty(key: "tags", value: .list(["数学", "線形代数"])),
                NoteProperty(key: "aliases", value: .list(["eigenvalue", "固有値"])),
            ]
        )
        #expect(analysis.body == "本文")
    }

    @Test("title がなければ最初の # 見出しをタイトルにする")
    func titleFallsBackToFirstHeading() {
        #expect(MarkdownAnalyzer.analyze("## 小見出し\n# 大見出し\n", path: "a.md").title == "大見出し")
        #expect(MarkdownAnalyzer.analyze("本文だけ", path: "a.md").title == nil)
    }

    @Test("フロントマターと本文のタグを重複なく集める")
    func collectsTags() {
        let analysis = MarkdownAnalyzer.analyze(
            "---\ntags: [量子計算]\n---\n本文 #量子計算 と #研究/VQE。#123 と a#b と `#code` は違う",
            path: "a.md"
        )
        #expect(analysis.tags == ["量子計算", "研究/VQE"])
    }

    @Test("[[リンク]] と相対リンクを集める。表示名と見出しは除く")
    func collectsLinks() {
        let analysis = MarkdownAnalyzer.analyze(
            """
            [[量子ゲート]]、[[数学/線形代数/ベクトル|ベクトル]]、[[固有値・固有状態#測定|測定]]
            [レポート](実験レポート.html) と ![図](../資料/図.png) と [外](https://example.com)
            """,
            path: "量子計算/量子ビット.md"
        )
        #expect(
            analysis.links == [
                NoteLinkReference(target: "量子ゲート", isExactPath: false),
                NoteLinkReference(target: "数学/線形代数/ベクトル", isExactPath: false),
                NoteLinkReference(target: "固有値・固有状態", isExactPath: false),
                NoteLinkReference(target: "量子計算/実験レポート.html", isExactPath: true),
            ]
        )
    }

    @Test("コードブロック、インラインコード、数式の中はリンクにしない")
    func ignoresLinksInCodeAndMath() {
        let analysis = MarkdownAnalyzer.analyze(
            """
            ```
            [[図の中]]
            ```
            `[[コード]]` と $[[n,k,d]]$ と
            $$
            [[ディスプレイ数式]]
            $$
            ~~~swift
            [[チルダ]]
            ~~~
            [[本物]]
            """,
            path: "a.md"
        )
        #expect(analysis.links.map(\.target) == ["本物"])
    }

    @Test("両端が空白の $ は数式ではない")
    func dollarWithSpacesIsNotMath() {
        let analysis = MarkdownAnalyzer.analyze("値段は $ 5 と [[リンク]] と $ 10", path: "a.md")
        #expect(analysis.links.map(\.target) == ["リンク"])
    }
}

@Suite("Frontmatter")
struct FrontmatterTests {
    @Test("閉じていないフロントマターは本文として扱う")
    func unclosedFrontmatterIsBody() {
        let source = "---\ntitle: a\n本文"
        #expect(Frontmatter.split(source).frontmatter == nil)
        #expect(Frontmatter.split(source).body == source)
    }

    @Test("コメントと空行を無視し、引用符を外す")
    func ignoresCommentsAndUnquotes() {
        let properties = Frontmatter.parse("# コメント\n\nsource: 'NeurIPS 2017'\ndate: 2026-09-29")
        #expect(
            properties == [
                NoteProperty(key: "source", value: .text("NeurIPS 2017")),
                NoteProperty(key: "date", value: .text("2026-09-29")),
            ]
        )
    }
}

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
