//
//  EditorView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import NotesFeature
import SwiftUI

/// 中央のエディタ。上にタブ、その下に選んだタブの中身を出す。
struct EditorView: View {
    let workspace: WorkspaceViewModel
    let cache: DocumentViewCache
    let showTag: (String) -> Void

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
                        DocumentView(
                            document: workspace.document(for: path),
                            cache: cache,
                            openLink: { target, isExactPath in
                                Task { await workspace.openLink(target, isExactPath: isExactPath) }
                            },
                            showTag: showTag
                        )
                    case .tool(let tool):
                        ToolPlaceholderView(tool: tool)
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
struct ToolPlaceholderView: View {
    let tool: WorkspaceTool

    var body: some View {
        ContentUnavailableView {
            Label(tool.title, systemImage: tool.systemImage)
        } description: {
            Text("フェーズ \(tool.plannedPhase) で実装します。")
        }
    }
}
