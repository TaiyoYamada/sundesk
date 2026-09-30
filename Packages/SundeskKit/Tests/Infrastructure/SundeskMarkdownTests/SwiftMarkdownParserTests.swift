//
//  SwiftMarkdownParserTests.swift
//  SundeskMarkdownTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import SundeskMarkdown
import Testing

@Suite("SwiftMarkdownParser")
struct SwiftMarkdownParserTests {
    @Test("フロントマターのプロパティを読む")
    func readsFrontmatterProperties() {
        let analysis = SwiftMarkdownParser().analyze(
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
        #expect(SwiftMarkdownParser().analyze("## 小見出し\n# 大見出し\n", path: "a.md").title == "大見出し")
        #expect(SwiftMarkdownParser().analyze("本文だけ", path: "a.md").title == nil)
    }

    @Test("フロントマターと本文のタグを重複なく集める")
    func collectsTags() {
        let analysis = SwiftMarkdownParser().analyze(
            "---\ntags: [量子計算]\n---\n本文 #量子計算 と #研究/VQE。#123 と a#b と `#code` は違う",
            path: "a.md"
        )
        #expect(analysis.tags == ["量子計算", "研究/VQE"])
    }

    @Test("[[リンク]] と相対リンクを集める。表示名と見出しは除く")
    func collectsLinks() {
        let analysis = SwiftMarkdownParser().analyze(
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
        let analysis = SwiftMarkdownParser().analyze(
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

    @Test("見出しと、その行番号（フロントマターの行も数える）")
    func collectsHeadings() {
        let analysis = SwiftMarkdownParser().analyze(
            "---\ntitle: a\n---\n# 大見出し\n\n```\n# コードの中\n```\n## 小見出し ##", path: "a.md")
        #expect(
            analysis.headings == [
                NoteHeading(level: 1, text: "大見出し", line: 4),
                NoteHeading(level: 2, text: "小見出し", line: 9),
            ]
        )
    }

    @Test("両端が空白の $ は数式ではない")
    func dollarWithSpacesIsNotMath() {
        let analysis = SwiftMarkdownParser().analyze("値段は $ 5 と [[リンク]] と $ 10", path: "a.md")
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
