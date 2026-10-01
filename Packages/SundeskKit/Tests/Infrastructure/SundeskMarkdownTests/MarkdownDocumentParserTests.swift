//
//  MarkdownDocumentParserTests.swift
//  SundeskMarkdownTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskMarkdown
import Testing

@Suite("MarkdownDocumentParser")
struct MarkdownDocumentParserTests {
    private func parse(_ source: String, path: String = "数学/固有値.md") -> [MarkdownBlock] {
        MarkdownDocumentParser.parse(source, notePath: path).blocks
    }

    @Test("フロントマターは表示しない。見出しには順番をつける")
    func skipsFrontmatterAndNumbersHeadings() {
        let blocks = parse(
            """
            ---
            title: 固有値
            ---
            # 固有値
            ## 定義
            本文
            ## 例
            """
        )

        #expect(
            blocks == [
                .heading(level: 1, content: [.text("固有値")], index: 0),
                .heading(level: 2, content: [.text("定義")], index: 1),
                .paragraph([.text("本文")]),
                .heading(level: 2, content: [.text("例")], index: 2),
            ]
        )
    }

    @Test("数式は Markdown として解釈しない（`_` や `\\\\` を守る）")
    func protectsMath() {
        let blocks = parse(
            #"""
            行列 $A_{ij} = a_i b_j$ の話。

            $$
            \begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}
            $$
            """#
        )

        #expect(
            blocks == [
                .paragraph([.text("行列 "), .math("A_{ij} = a_i b_j"), .text(" の話。")]),
                .math(#"\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}"#),
            ]
        )
    }

    @Test("```math のコードブロックもディスプレイ数式にする")
    func mathCodeBlock() {
        #expect(parse("```math\nE = mc^2\n```") == [.math("E = mc^2")])
    }

    @Test("[[リンク]] と表示名。表の中の \\| も区切りとして扱う")
    func wikilinks() {
        let blocks = parse(
            """
            [[量子ビット]] と [[線形代数#固有値|固有値の節]]

            | 名前 | リンク |
            | --- | :-: |
            | a | [[ブラ・ケット記法\\|ブラケット]] |
            """
        )

        #expect(
            blocks[0]
                == .paragraph([
                    .wikilink(target: "量子ビット", label: "量子ビット"),
                    .text(" と "),
                    .wikilink(target: "線形代数", label: "固有値の節"),
                ])
        )
        #expect(
            blocks[1]
                == .table(
                    header: [[.text("名前")], [.text("リンク")]],
                    rows: [[[.text("a")], [.wikilink(target: "ブラ・ケット記法", label: "ブラケット")]]],
                    alignments: [.leading, .center]
                )
        )
    }

    @Test("コードの中の $ や [[ ]] はそのまま残す")
    func keepsCodeAsIs() {
        let blocks = parse(
            """
            `$HOME` と `[[x]]`

            ```swift
            let price = "$5 and $10"
            ```
            """
        )

        #expect(
            blocks == [
                .paragraph([.code("$HOME"), .text(" と "), .code("[[x]]")]),
                .code(language: "swift", code: #"let price = "$5 and $10""#),
            ]
        )
    }

    @Test("注記（> [!kind]）")
    func callouts() {
        let blocks = parse(
            """
            > [!tip] 覚え方
            > 固有ベクトルは **向き** が変わらない。

            > [!warning]
            > 注意書き

            > ただの引用
            """
        )

        #expect(
            blocks == [
                .callout(
                    kind: "tip", title: "覚え方",
                    content: [.paragraph([.text("固有ベクトルは "), .strong([.text("向き")]), .text(" が変わらない。")])]
                ),
                .callout(kind: "warning", title: "注意", content: [.paragraph([.text("注意書き")])]),
                .quote([.paragraph([.text("ただの引用")])]),
            ]
        )
    }

    @Test("タスクリストと入れ子のリスト")
    func lists() {
        let blocks = parse(
            """
            - [x] 済んだ
            - [ ] まだ
              1. 入れ子
            """
        )

        #expect(
            blocks == [
                .list(
                    ordered: false, start: 1,
                    items: [
                        MarkdownListItem(checkbox: true, blocks: [.paragraph([.text("済んだ")])]),
                        MarkdownListItem(
                            checkbox: false,
                            blocks: [
                                .paragraph([.text("まだ")]),
                                .list(
                                    ordered: true, start: 1,
                                    items: [MarkdownListItem(checkbox: nil, blocks: [.paragraph([.text("入れ子")])])]
                                ),
                            ]
                        ),
                    ]
                )
            ]
        )
    }

    @Test("リンクの行き先: 外部、Vault の中（相対パスを解決）、見出し")
    func linkTargets() {
        let blocks = parse(
            "[a](https://example.com) [b](../量子計算/量子ビット.md) [c](#定義)",
            path: "数学/固有値.md"
        )

        #expect(
            blocks == [
                .paragraph([
                    .link(target: .external(URL(string: "https://example.com")!), content: [.text("a")]),
                    .text(" "),
                    .link(target: .vault("量子計算/量子ビット.md"), content: [.text("b")]),
                    .text(" "),
                    .link(target: .anchor("定義"), content: [.text("c")]),
                ])
            ]
        )
    }

    @Test("画像だけの段落は画像のブロックにする")
    func imageBlock() {
        let blocks = parse("![図](images/図.png)", path: "数学/固有値.md")

        #expect(blocks == [.image(MarkdownImage(source: .vault("数学/images/図.png"), alt: "図"))])
    }

    @Test("本文の #タグ を分ける")
    func tags() {
        #expect(
            parse("メモ #線形代数 と #量子/基礎")
                == [.paragraph([.text("メモ "), .tag("線形代数"), .text(" と "), .tag("量子/基礎")])]
        )
    }

    @Test("強調、打ち消し、改行、区切り線")
    func inlineStyles() {
        let blocks = parse("*斜体* ~~消す~~\n次の行\n\n---")

        #expect(
            blocks == [
                .paragraph([
                    .emphasis([.text("斜体")]), .text(" "), .strikethrough([.text("消す")]), .softBreak,
                    .text("次の行"),
                ]),
                .rule,
            ]
        )
    }
}
