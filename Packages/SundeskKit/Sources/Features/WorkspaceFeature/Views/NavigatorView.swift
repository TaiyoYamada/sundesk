//
//  NavigatorView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import NotesFeature
import SwiftUI

/// 左のナビゲータ。上のアイコンで「ファイル」「検索」「タグ」を切り替える（Xcode と同じ）。
struct NavigatorView: View {
    @Bindable var workspace: WorkspaceViewModel
    let navigator: FileNavigatorViewModel
    let search: SearchViewModel
    let tags: TagsViewModel

    var body: some View {
        // サイドバーはツールバーの下まで伸びるので、切り替えのアイコンはリストの上端の余白に置く
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
            Picker("ナビゲータ", selection: $workspace.navigatorMode) {
                ForEach(WorkspaceViewModel.NavigatorMode.allCases) { mode in
                    Image(systemName: mode.systemImage)
                        .help(mode.title)
                        .accessibilityLabel(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                ToolBarView(workspace: workspace)
            }
        }
    }
}

/// ナビゲータの下に並べる機能（タブで開く）。場所を取らないよう、アイコンを 1 行に並べる。
private struct ToolBarView: View {
    let workspace: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceTool.allCases) { tool in
                let isSelected = workspace.selectedTab?.content == .tool(tool)
                Button {
                    workspace.open(tool: tool)
                } label: {
                    Image(systemName: tool.systemImage)
                        .imageScale(.large)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .help(tool.title)
                .accessibilityLabel(tool.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
