//
//  SidebarNodeRow.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// サイドバーの木の 1 行。中があれば開閉でき、その中の行も同じ形で並べる。
struct SidebarNodeRow: View {
    let node: SidebarNode
    @Bindable var viewModel: LibraryViewModel
    let actions: SidebarActions

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { SidebarNodeRow(node: $0, viewModel: viewModel, actions: actions) }
            } label: {
                label
            }
        } else {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        switch (node.kind, node.id) {
        case (.collection, .collection(let id)):
            Label(node.name, systemImage: "folder")
                .tag(node.id)
                .contextMenu { collectionMenu(id) }
                .draggable(SidebarActions.collectionPrefix + id.uuidString)
                .dropDestination(for: String.self) { items, _ in actions.drop(items, id) }
        case (.reference(let hasPDF), .reference(let id, let collectionID)):
            Label(node.name, systemImage: hasPDF ? "doc.text" : "doc")
                .lineLimit(1)
                .help(node.name)
                .tag(node.id)
                .draggable(id.uuidString)
                .contextMenu { referenceMenu(id, in: collectionID) }
        default:
            Label(node.name, systemImage: "tray")
                .tag(node.id)
        }
    }

    @ViewBuilder
    private func collectionMenu(_ id: UUID) -> some View {
        Button("この中に新しいコレクション…") { actions.createCollection(id) }
        Button("名前を変える…") { actions.renameCollection(id) }
        if !viewModel.isTopLevelCollection(id) {
            Button("一番上の階層へ移す") { Task { await viewModel.moveCollection(id, into: nil) } }
        }
        Divider()
        Button("削除…", role: .destructive) { actions.deleteCollection(id) }
    }

    @ViewBuilder
    private func referenceMenu(_ id: UUID, in collectionID: UUID?) -> some View {
        Button("既定のアプリで開く") { Task { await viewModel.openPDFExternally(id) } }
        if let collectionID {
            Button("このコレクションから外す") { Task { await viewModel.remove([id], fromCollection: collectionID) } }
        }
        Divider()
        Button("削除…", role: .destructive) { actions.deleteReference(id) }
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { viewModel.expandedItems.contains(node.id) },
            set: { isOpen in
                if isOpen {
                    viewModel.expandedItems.insert(node.id)
                } else {
                    viewModel.expandedItems.remove(node.id)
                }
            })
    }
}

/// サイドバーの行から呼ぶ操作（名前を聞くアラートと、削除の確認は ``LibrarySidebar`` が出す）。
struct SidebarActions {
    /// コレクションをドラッグするときの文字の頭（論文の行は ID だけを運ぶ）。
    static let collectionPrefix = "sundesk-collection:"

    let createCollection: (UUID?) -> Void
    let renameCollection: (UUID) -> Void
    let deleteCollection: (UUID) -> Void
    let deleteReference: (UUID) -> Void
    /// ドラッグされたもの（コレクションか論文）を、コレクションへ入れる。
    let drop: ([String], UUID) -> Void
}
