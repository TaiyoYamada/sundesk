//
//  EditorView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

/// 中央のエディタ。上にタブ、その下に選んだタブの中身を出す。
struct EditorView: View {
    let workspace: WorkspaceViewModel
    let pages: RenderedPageCache

    var body: some View {
        VStack(spacing: 0) {
            if !workspace.tabs.isEmpty {
                TabBarView(workspace: workspace)
                Divider()
            }
            Group {
                if let tab = workspace.selectedTab {
                    switch tab.content {
                    case .document(let path):
                        DocumentView(document: workspace.document(for: path), workspace: workspace, pages: pages)
                    case .feature(let feature):
                        FeaturePlaceholderView(feature: feature)
                    }
                } else {
                    ContentUnavailableView {
                        Label("ファイルを開いていません", systemImage: "doc.text")
                    } description: {
                        Text("左のナビゲータからファイルを選んでください。")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// まだ作っていない機能の画面。
struct FeaturePlaceholderView: View {
    let feature: WorkspaceFeature

    var body: some View {
        ContentUnavailableView {
            Label(feature.title, systemImage: feature.systemImage)
        } description: {
            Text("フェーズ \(feature.plannedPhase) で実装します。")
        }
    }
}
