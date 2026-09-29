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
import LibraryFeature
import NotesFeature
import SwiftUI

/// 中央のエディタ。上にタブ、その下に選んだタブの中身を出す。
struct EditorView: View {
    let workspace: WorkspaceViewModel
    let cache: DocumentViewCache
    let screens: LibraryScreenCache
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
                    case .paper(let key):
                        // 同じ種類のタブを切り替えても読み直すよう、キーごとに別の画面にする
                        PaperScreen(viewModel: screens.paper(key)) { note(for: tab) }
                            .id(tab.id)
                    case .experiment(let key):
                        ExperimentScreen(viewModel: screens.experiment(key), openPath: openLibraryPath) {
                            note(for: tab)
                        }
                        .id(tab.id)
                    case .comparison(let keys):
                        ComparisonScreen(viewModel: screens.comparison(keys)) { key, title in
                            workspace.open(experiment: key, title: title)
                        }
                        .id(tab.id)
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

extension EditorView {
    /// 論文や実験のタブの中の、メモのエディタ。
    @ViewBuilder
    fileprivate func note(for tab: WorkspaceTab) -> some View {
        if let path = tab.documentPath {
            DocumentView(
                document: workspace.document(for: path), cache: cache,
                openLink: { target, isExactPath in Task { await workspace.openLink(target, isExactPath: isExactPath) }
                },
                showTag: showTag)
        }
    }

    /// ライブラリのパス（論文や実験のフォルダ、ファイル）を開く。
    fileprivate func openLibraryPath(_ path: String) {
        let parts = path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Papers" {
            workspace.open(paper: parts[1], title: parts[1])
        } else if parts.count >= 2, parts[0] == "Experiments" {
            workspace.open(experiment: parts[1], title: parts[1])
        } else {
            workspace.open(path: path)
        }
    }
}

/// 論文、実験、比べる画面の ViewModel（タブを切り替えても作り直さない）。
@MainActor
final class LibraryScreenCache {
    private let dependencies: WorkspaceDependencies
    private var papers: [String: PaperViewModel] = [:]
    private var experiments: [String: ExperimentViewModel] = [:]
    private var comparisons: [[String]: ComparisonViewModel] = [:]

    init(dependencies: WorkspaceDependencies) {
        self.dependencies = dependencies
    }

    func paper(_ key: String) -> PaperViewModel {
        if let model = papers[key] { return model }
        let model = dependencies.makePaper(key)
        papers[key] = model
        return model
    }

    func experiment(_ key: String) -> ExperimentViewModel {
        if let model = experiments[key] { return model }
        let model = dependencies.makeExperiment(key)
        experiments[key] = model
        return model
    }

    func comparison(_ keys: [String]) -> ComparisonViewModel {
        if let model = comparisons[keys] { return model }
        let model = dependencies.makeComparison(keys)
        comparisons[keys] = model
        return model
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
