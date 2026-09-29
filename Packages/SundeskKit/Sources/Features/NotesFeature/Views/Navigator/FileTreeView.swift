//
//  FileTreeView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftUI

/// Vault のファイルの木。選んだファイルを開く。
public struct FileTreeView: View {
    @Bindable private var navigator: FileNavigatorViewModel
    private let selectedPath: String?
    private let rootPath: String?
    private let open: (String) -> Void

    /// - Parameters:
    ///   - selectedPath: 今開いているファイル。木の選択と連動させる。
    ///   - rootPath: このフォルダの下だけを出す（nil ならすべて）。
    ///   - open: ファイルを選んだときに呼ぶ。
    public init(
        navigator: FileNavigatorViewModel, selectedPath: String?, rootPath: String? = nil,
        open: @escaping (String) -> Void
    ) {
        self.navigator = navigator
        self.selectedPath = selectedPath
        self.rootPath = rootPath
        self.open = open
    }

    private var shownItems: [NavigatorItem] {
        guard let rootPath else { return navigator.items }
        return navigator.items.first { $0.id == rootPath }?.children ?? []
    }

    public var body: some View {
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
                    OutlineGroup(shownItems, children: \.children) { item in
                        Label(item.name, systemImage: item.systemImage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(item.id)
                            .contextMenu { contextMenu(for: item) }
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
                if navigator.isSyncing {
                    ProgressView().controlSize(.mini)
                        .help("Vault を同期しています")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { selectedPath },
            set: { path in
                guard let path, navigator.isFile(path) else { return }
                open(path)
            }
        )
    }

    @ViewBuilder
    private func contextMenu(for item: NavigatorItem) -> some View {
        if !item.isFolder {
            Button("開く") { open(item.id) }
        }
        Button("Finder で表示") {
            NSWorkspace.shared.activateFileViewerSelecting([navigator.fileURL(for: item.id)])
        }
    }
}
