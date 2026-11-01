//
//  SidebarTree.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// サイドバーの木と、「コレクションに追加」のメニューの並びを組む。
struct SidebarTree {
    let references: [Reference]
    let collections: [ReferenceCollection]

    /// コレクションの木。中のコレクションを先に、その後に論文を並べる。
    func collectionNodes(parentID: UUID?) -> [SidebarNode] {
        sorted(collections.filter { $0.parentID == parentID })
            .map { collection in
                let papers = references.filter { $0.collectionIDs.contains(collection.id) }
                let children = collectionNodes(parentID: collection.id) + referenceNodes(papers, parent: collection.id)
                return SidebarNode(
                    id: .collection(collection.id), name: collection.name, kind: .collection,
                    children: children.isEmpty ? nil : children)
            }
    }

    /// 「未整理」の行。中に、どのコレクションにも入っていない論文を並べる。
    var unfiledNode: SidebarNode {
        let children = referenceNodes(references.filter { $0.collectionIDs.isEmpty }, parent: nil)
        return SidebarNode(id: .unfiled, name: "未整理", kind: .unfiled, children: children.isEmpty ? nil : children)
    }

    /// コレクションを木の順に平らにしたもの（「研究 / 最適化」）。
    func choices(parentID: UUID?, prefix: String) -> [CollectionChoice] {
        sorted(collections.filter { $0.parentID == parentID })
            .flatMap { collection in
                let path = prefix + collection.name
                return [CollectionChoice(id: collection.id, path: path)]
                    + choices(parentID: collection.id, prefix: path + " / ")
            }
    }

    /// 論文の行。名前は PDF のファイル名（拡張子なし）。PDF がなければ題名。
    private func referenceNodes(_ papers: [Reference], parent: UUID?) -> [SidebarNode] {
        papers.map { reference in
            let name = reference.attachment.map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
            return SidebarNode(
                id: .reference(reference.id, parent: parent), name: name ?? reference.metadata.title,
                kind: .reference(hasPDF: reference.attachment != nil), children: nil)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func sorted(_ collections: [ReferenceCollection]) -> [ReferenceCollection] {
        collections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
