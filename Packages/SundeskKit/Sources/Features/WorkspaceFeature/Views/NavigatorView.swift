//
//  NavigatorView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import NotesFeature
import SwiftUI

/// 左のナビゲータ。上のアイコンの列（Xcode と同じ）で、「ファイル」「検索」「タグ」を切り替え、機能をタブで開く。
struct NavigatorView: View {
    @Bindable var workspace: WorkspaceViewModel
    let navigator: FileNavigatorViewModel
    let search: SearchViewModel
    let tags: TagsViewModel

    var body: some View {
        // サイドバーはツールバーの下まで伸びるので、アイコンの列はリストの上端の余白に置く
        Group {
            switch workspace.navigatorMode {
            case .files:
                FileTreeView(navigator: navigator, selectedPath: workspace.selectedTab?.documentPath) {
                    workspace.open(path: $0)
                }
            case .search:
                SearchNavigatorView(search: search) { workspace.open(path: $0) }
            case .tags:
                TagNavigatorView(tags: tags) { workspace.open(path: $0) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                NavigatorBar(workspace: workspace)
                Divider()
            }
        }
    }
}

/// ナビゲータの上のアイコンの列。左の 3 つでナビゲータを切り替え、右の 5 つで機能をタブで開く。
private struct NavigatorBar: View {
    let workspace: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceViewModel.NavigatorMode.allCases) { mode in
                item(mode.title, mode.systemImage, isSelected: workspace.navigatorMode == mode) {
                    workspace.navigatorMode = mode
                }
                .accessibilityAddTraits(workspace.navigatorMode == mode ? .isSelected : [])
            }
            Divider().frame(height: 16).padding(.horizontal, 2)
            ForEach(WorkspaceTool.allCases) { tool in
                item(tool.title, tool.systemImage, isSelected: workspace.selectedTab?.content == .tool(tool)) {
                    workspace.open(tool: tool)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private func item(
        _ title: String, _ systemImage: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .help(title)
        .accessibilityLabel(title)
    }
}
