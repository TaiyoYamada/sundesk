//
//  VaultNodeTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain
import Testing

@Suite("VaultNode")
struct VaultNodeTests {
    private let tree = VaultNode(
        id: "",
        name: "Vault",
        kind: .folder,
        children: [
            VaultNode(id: "ホーム.md", name: "ホーム.md", kind: .markdown),
            VaultNode(
                id: "量子計算",
                name: "量子計算",
                kind: .folder,
                children: [
                    VaultNode(id: "量子計算/量子ビット.md", name: "量子ビット.md", kind: .markdown),
                    VaultNode(id: "量子計算/レポート.html", name: "レポート.html", kind: .html),
                ]
            ),
            VaultNode(id: "10.md", name: "10.md", kind: .markdown),
            VaultNode(id: "2.md", name: "2.md", kind: .markdown),
        ]
    )

    @Test("フォルダを先に、名前は数字を数として並べる")
    func sortsFoldersFirstThenNaturally() {
        #expect(tree.children?.map(\.name) == ["量子計算", "2.md", "10.md", "ホーム.md"])
    }

    @Test("すべてのファイルを平らに取り出す")
    func filesFlattensTree() {
        #expect(Set(tree.files.map(\.path)) == ["ホーム.md", "量子計算/量子ビット.md", "量子計算/レポート.html", "10.md", "2.md"])
    }

    @Test("パスでノードを探す")
    func findsNodeByPath() {
        #expect(tree.node(at: "量子計算/レポート.html")?.kind == .html)
        #expect(tree.node(at: "ない.md") == nil)
    }

    @Test("名前で絞り込むと、一致したファイルとその親だけが残る")
    func filtersByName() {
        let filtered = tree.filtered(by: "ビット")
        #expect(filtered?.files.map(\.path) == ["量子計算/量子ビット.md"])
        #expect(tree.filtered(by: "  ") == tree)
    }

    @Test("拡張子を除いた名前")
    func stemRemovesExtension() {
        #expect(VaultNode(id: "a/量子ビット.md", name: "量子ビット.md", kind: .markdown).stem == "量子ビット")
        #expect(VaultNode(id: "a", name: "a.b", kind: .folder, children: []).stem == "a.b")
    }
}
