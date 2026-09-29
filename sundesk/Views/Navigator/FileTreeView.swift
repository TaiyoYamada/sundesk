//
//  FileTreeView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskComposition
import SundeskDomain
import SundeskPresentation
import SwiftUI

/// Vault のファイルの木。選んだファイルをタブで開く。
struct FileTreeView: View {
    let workspace: WorkspaceViewModel
    @InjectedObservable(\.fileNavigatorViewModel) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        Group {
            if let message = navigator.errorMessage {
                ContentUnavailableView {
                    Label("Vault を開けません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    SettingsLink { Text("設定を開く…") }
                }
            } else {
                List(selection: selection) {
                    OutlineGroup(navigator.visibleNodes, children: \.children) { node in
                        Label(node.name, systemImage: node.kind.systemImage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(node.path)
                            .contextMenu { contextMenu(for: node) }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("file-tree")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("名前で絞り込む", text: $navigator.filterText)
                    .textFieldStyle(.plain)
                if navigator.isIndexing {
                    ProgressView().controlSize(.mini)
                        .help("索引を更新しています")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }

    /// 選んだファイルを開く。選択は、開いているタブと連動させる。
    private var selection: Binding<String?> {
        Binding(
            get: { workspace.selectedTab?.documentPath },
            set: { path in
                guard let path, navigator.tree?.node(at: path)?.isFolder == false else { return }
                workspace.open(path: path)
            }
        )
    }

    @ViewBuilder
    private func contextMenu(for node: VaultNode) -> some View {
        if !node.isFolder {
            Button("開く") { workspace.open(path: node.path) }
        }
        Button("Finder で表示") {
            NSWorkspace.shared.activateFileViewerSelecting([VaultSettings.directory().appending(path: node.path)])
        }
    }
}
