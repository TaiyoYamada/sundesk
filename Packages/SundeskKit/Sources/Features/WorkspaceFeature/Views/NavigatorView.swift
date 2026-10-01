//
//  NavigatorView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import LibraryFeature
import NotesFeature
import SwiftUI

/// 左のナビゲータ。上のアイコンの列（Xcode と同じ）で、「ファイル」「検索」「タグ」を切り替え、機能をタブで開く。
struct NavigatorView: View {
    @Bindable var workspace: WorkspaceViewModel
    let navigator: FileNavigatorViewModel
    let search: SearchViewModel
    let tags: TagsViewModel
    let library: LibraryViewModel

    /// 種類ごとに、続けてフォルダのまま出す、読むだけでつないだフォルダ。
    static func extraRoots(for section: LibraryViewModel.Section) -> [TreeRoot] {
        switch section {
        case .notes: [TreeRoot(path: "study-artifact", title: "study-artifact")]
        case .experiments: [TreeRoot(path: "Research/experiment", title: "Research の実験")]
        case .data: [TreeRoot(path: "Research", title: "Research")]
        case .papers, .materials: []
        }
    }

    static func treeBundle(_ bundle: LibraryBundle) -> TreeBundle {
        TreeBundle(
            title: bundle.title, subtitle: bundle.subtitle, systemImage: bundle.systemImage, isLeaf: bundle.isLeaf)
    }

    /// 開いているタブに当たる、木の中のパス（論文や実験はフォルダ）。
    private var selectedTreePath: String? {
        switch workspace.selectedTab?.content {
        case .document(let path): path
        case .paper(let key): "Papers/\(key)"
        case .experiment(let key): "Experiments/\(key)"
        case .researchProject(let path), .researchRun(let path): path
        case .tool, .comparison, nil: nil
        }
    }

    /// 木で選んだものを開く。1 つのものとして見せるフォルダは、その画面で開く。
    private func openTreePath(_ path: String) {
        if let bundle = library.bundles[path] {
            open(bundle.destination)
        } else {
            workspace.open(path: path)
        }
    }

    private func open(_ destination: LibraryDestination) {
        switch destination {
        case .file(let path): workspace.open(path: path)
        case .paper(let key, let title): workspace.open(paper: key, title: title)
        case .experiment(let key, let title): workspace.open(experiment: key, title: title)
        case .comparison(let keys): workspace.open(comparison: keys)
        case .researchProject(let path, let title): workspace.open(researchProject: path, title: title)
        case .researchRun(let path, let title): workspace.open(researchRun: path, title: title)
        }
    }

    var body: some View {
        // サイドバーはツールバーの下まで伸びるので、アイコンの列はリストの上端の余白に置く
        Group {
            switch workspace.navigatorMode {
            case .library:
                LibraryNavigatorView(viewModel: library) { section in
                    FileTreeView(
                        navigator: navigator, selectedPath: selectedTreePath, rootPath: section.folder,
                        extraRoots: Self.extraRoots(for: section),
                        bundle: { path in library.bundles[path].map(Self.treeBundle) },
                        selectionChanged: { library.selectedPaths = $0 },
                        open: openTreePath)
                } open: { destination in
                    open(destination)
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
///
/// Xcode と同じく、列をガラスのカプセル（Liquid Glass）に載せ、選んでいるものの下の丸みを、選び直すと滑らせて動かす。
private struct NavigatorBar: View {
    let workspace: WorkspaceViewModel
    @Namespace private var selection

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(WorkspaceViewModel.NavigatorMode.allCases) { mode in
                    item(mode.title, mode.systemImage, group: "mode", isSelected: workspace.navigatorMode == mode) {
                        withAnimation(.snappy(duration: 0.25)) { workspace.navigatorMode = mode }
                    }
                    .accessibilityAddTraits(workspace.navigatorMode == mode ? .isSelected : [])
                }
                Divider().frame(height: 14).padding(.horizontal, 3)
                ForEach(WorkspaceTool.allCases) { tool in
                    item(
                        tool.title, tool.systemImage, group: "tool",
                        isSelected: workspace.selectedTab?.content == .tool(tool)
                    ) {
                        withAnimation(.snappy(duration: 0.25)) { workspace.open(tool: tool) }
                    }
                }
            }
            .padding(3)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func item(
        _ title: String, _ systemImage: String, group: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(.capsule)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.tint.opacity(0.18))
                            .matchedGeometryEffect(id: group, in: selection)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .help(title)
        .accessibilityLabel(title)
    }
}
