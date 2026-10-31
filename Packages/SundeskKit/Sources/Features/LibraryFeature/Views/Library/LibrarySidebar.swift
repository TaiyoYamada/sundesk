//
//  LibrarySidebar.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// ライブラリ、コレクション、タグのサイドバー。文献の行をコレクションへドラッグすると、そこに入れる。
struct LibrarySidebar: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var naming: Naming?
    @State private var name = ""
    @State private var pendingDeletion: UUID?

    /// 名前を入れてもらう操作。
    private enum Naming {
        case create(parentID: UUID?)
        case rename(UUID)
    }

    var body: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section("ライブラリ") {
                Label("すべての文献", systemImage: "books.vertical").tag(SidebarItem.all)
                Label("未整理", systemImage: "tray").tag(SidebarItem.unfiled)
            }
            Section("コレクション") {
                OutlineGroup(viewModel.collectionTree, children: \.children) { node in
                    Label(node.name, systemImage: "folder")
                        .tag(SidebarItem.collection(node.id))
                        .contextMenu { menu(for: node.id) }
                        .dropDestination(for: String.self) { items, _ in
                            drop(items, into: node.id)
                        }
                }
            }
            if !viewModel.tags.isEmpty {
                Section("タグ") {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag").tag(SidebarItem.tag(tag))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("新しいコレクション", systemImage: "folder.badge.plus") { startNaming(.create(parentID: nil)) }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
        }
        .alert(naming.map(title) ?? "", isPresented: isNaming) {
            TextField("名前", text: $name)
            Button("OK") { commitName() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("コレクションを削除しますか？", isPresented: isConfirmingDeletion) {
            Button("削除", role: .destructive) {
                guard let id = pendingDeletion else { return }
                Task { await viewModel.deleteCollection(id) }
            }
        } message: {
            Text("中のコレクションも消えます。文献はライブラリに残ります。")
        }
    }

    @ViewBuilder
    private func menu(for id: UUID) -> some View {
        Button("この中に新しいコレクション…") { startNaming(.create(parentID: id)) }
        Button("名前を変える…") { startNaming(.rename(id)) }
        Divider()
        Button("削除…", role: .destructive) { pendingDeletion = id }
    }

    /// ドラッグされた行が選んでいる行の 1 つなら、選んでいる行をすべて入れる。
    private func drop(_ items: [String], into collectionID: UUID) {
        let dropped = Set(items.compactMap(UUID.init(uuidString:)))
        guard !dropped.isEmpty else { return }
        let ids = dropped.isSubset(of: viewModel.selection) ? viewModel.selection : dropped
        Task { await viewModel.add(ids, toCollection: collectionID) }
    }

    private func startNaming(_ value: Naming) {
        if case .rename(let id) = value {
            name = viewModel.collectionName(id)
        } else {
            name = ""
        }
        naming = value
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let naming, !trimmed.isEmpty else { return }
        Task {
            switch naming {
            case .create(let parentID): await viewModel.createCollection(named: trimmed, parentID: parentID)
            case .rename(let id): await viewModel.renameCollection(id, to: trimmed)
            }
        }
    }

    private func title(_ naming: Naming) -> String {
        switch naming {
        case .create: "新しいコレクション"
        case .rename: "コレクションの名前"
        }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}
