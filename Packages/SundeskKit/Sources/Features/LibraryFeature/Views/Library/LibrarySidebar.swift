//
//  LibrarySidebar.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// ライブラリ、コレクション（中の論文を含む木）、タグのサイドバー。
/// 論文をコレクションへドラッグすると、そこに入れる。コレクションを別のコレクションへドラッグすると、その中へ移す。
struct LibrarySidebar: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var naming: Naming?
    @State private var name = ""
    @State private var pendingDeletion: UUID?
    @State private var pendingReferenceDeletion: UUID?

    /// 名前を入れてもらう操作。
    private enum Naming {
        case create(parentID: UUID?)
        case rename(UUID)
    }

    var body: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section("ライブラリ") {
                Label("すべての文献", systemImage: "books.vertical").tag(SidebarItem.all)
                SidebarNodeRow(node: viewModel.unfiledNode, viewModel: viewModel, actions: actions)
            }
            Section("コレクション") {
                ForEach(viewModel.collectionTree) { node in
                    SidebarNodeRow(node: node, viewModel: viewModel, actions: actions)
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
                Menu {
                    Button("一番上に新しいコレクション…") { startNaming(.create(parentID: nil)) }
                    if let id = viewModel.selectedCollectionID {
                        Button("「\(viewModel.collectionName(id))」の中に新しいコレクション…") {
                            startNaming(.create(parentID: id))
                        }
                    }
                } label: {
                    Label("新しいコレクション", systemImage: "folder.badge.plus")
                } primaryAction: {
                    // 選んでいるコレクションがあれば、その中に作る
                    startNaming(.create(parentID: viewModel.selectedCollectionID))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
        .confirmationDialog("この文献を削除しますか？", isPresented: isConfirmingReferenceDeletion) {
            Button("削除", role: .destructive) {
                guard let id = pendingReferenceDeletion else { return }
                Task { await viewModel.delete([id]) }
            }
        } message: {
            Text("添付した PDF、注釈、メモも消えます。")
        }
    }

    private var actions: SidebarActions {
        SidebarActions(
            createCollection: { startNaming(.create(parentID: $0)) },
            renameCollection: { startNaming(.rename($0)) },
            deleteCollection: { pendingDeletion = $0 },
            deleteReference: { pendingReferenceDeletion = $0 },
            drop: drop)
    }

    /// コレクションなら中へ移す。文献の行なら入れる。ドラッグされた行が選んでいる行の 1 つなら、選んでいる行をすべて入れる。
    private func drop(_ items: [String], into collectionID: UUID) {
        let prefix = SidebarActions.collectionPrefix
        let collections = items.filter { $0.hasPrefix(prefix) }
            .compactMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }
        for id in collections {
            Task { await viewModel.moveCollection(id, into: collectionID) }
        }
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

    private var isConfirmingReferenceDeletion: Binding<Bool> {
        Binding(get: { pendingReferenceDeletion != nil }, set: { if !$0 { pendingReferenceDeletion = nil } })
    }
}
