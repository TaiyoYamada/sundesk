//
//  NavigatorView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

/// 左のナビゲータ。上のアイコンで「ファイル」「検索」「タグ」を切り替える（Xcode と同じ）。
struct NavigatorView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        // サイドバーはツールバーの下まで伸びるので、切り替えのアイコンはリストの上端の余白に置く
        Group {
            switch workspace.navigatorMode {
            case .files: FileTreeView(workspace: workspace)
            case .search: SearchNavigatorView(workspace: workspace)
            case .tags: TagNavigatorView(workspace: workspace)
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
                FeatureListView(workspace: workspace)
            }
        }
    }
}

/// ナビゲータの下に並べる機能（タブで開く）。場所を取らないよう、アイコンを 1 行に並べる。
private struct FeatureListView: View {
    let workspace: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceFeature.allCases) { feature in
                let isSelected = workspace.selectedTab?.content == .feature(feature)
                Button {
                    workspace.open(feature: feature)
                } label: {
                    Image(systemName: feature.systemImage)
                        .imageScale(.large)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .help(feature.title)
                .accessibilityLabel(feature.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
