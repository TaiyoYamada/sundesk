//
//  EditorView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import ChatFeature
import GraphFeature
import ImagesFeature
import LabFeature
import NotesFeature
import SwiftUI

/// 中央のエディタ。上にタブ、その下に選んだタブの中身を出す。
struct EditorView: View {
    let workspace: WorkspaceViewModel
    let cache: DocumentViewCache
    let graph: GraphViewModel
    let chat: ChatViewModel
    let tools: ToolViewModels
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
                    case .tool(.graph):
                        GraphScreen(viewModel: graph)
                    case .tool(.chat):
                        ChatScreen(viewModel: chat) { path, line in workspace.open(path: path, line: line) }
                    case .tool(.lab):
                        LabScreen(viewModel: tools.lab, forge: tools.forge, scratch: tools.scratch)
                    case .tool(.models):
                        ModelsScreen(viewModel: tools.models)
                    case .tool(.images):
                        ImagesScreen(viewModel: tools.images)
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

/// ファイル以外のタブの ViewModel（ウインドウごと）。
@MainActor
struct ToolViewModels {
    let lab: LabViewModel
    let forge: ForgeViewModel
    let scratch: ScratchViewModel
    let models: ModelsViewModel
    let images: ImagesViewModel
}
