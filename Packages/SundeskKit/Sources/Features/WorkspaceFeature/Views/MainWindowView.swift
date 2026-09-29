//
//  MainWindowView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import NotesFeature
import SwiftUI

/// メインウインドウ。左にナビゲータ、中央にタブのエディタ、右にインスペクタを置く（ADR 0009）。
public struct MainWindowView: View {
    private let dependencies: WorkspaceDependencies
    @State private var workspace: WorkspaceViewModel
    @State private var search: SearchViewModel
    @State private var tags: TagsViewModel
    @State private var cache = DocumentViewCache()

    public init(dependencies: WorkspaceDependencies) {
        self.dependencies = dependencies
        _workspace = State(initialValue: dependencies.makeWorkspace())
        _search = State(initialValue: dependencies.makeSearch())
        _tags = State(initialValue: dependencies.makeTags())
    }

    public var body: some View {
        NavigationSplitView {
            NavigatorView(workspace: workspace, navigator: dependencies.fileNavigator, search: search, tags: tags)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            EditorView(workspace: workspace, cache: cache, showTag: showTag)
        }
        .inspector(isPresented: $workspace.isInspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 220, ideal: 260, max: 380)
        }
        .navigationTitle(workspace.selectedTab?.title ?? dependencies.fileNavigator.vaultName)
        .navigationSubtitle(workspace.selectedTab == nil ? "" : dependencies.fileNavigator.vaultName)
        .toolbar {
            if let document = workspace.selectedDocument, document.canToggleDisplayMode {
                ToolbarItem(placement: .primaryAction) {
                    DisplayModePicker(document: document)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                EngineStatusButton(viewModel: dependencies.engineStatus)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspace.isInspectorPresented.toggle()
                } label: {
                    Label("インスペクタ", systemImage: "sidebar.trailing")
                }
                .help("インスペクタを表示／非表示（⌥⌘0）")
            }
        }
        .alert(
            "開けませんでした",
            isPresented: Binding(
                get: { workspace.alertMessage != nil },
                set: { if !$0 { workspace.alertMessage = nil } }
            )
        ) {
            Button("OK") { workspace.alertMessage = nil }
        } message: {
            Text(workspace.alertMessage ?? "")
        }
        .focusedSceneValue(workspace)
        .onChange(of: workspace.tabs) { _, tabs in
            cache.keepOnly(paths: Set(tabs.compactMap(\.documentPath)))
        }
        .task { await dependencies.engineStatus.observe() }
        .task { await dependencies.fileNavigator.observe() }
    }

    /// タグのノートの一覧を、ナビゲータに出す。
    private func showTag(_ name: String) {
        workspace.navigatorMode = .tags
        tags.selectedTag = name
        Task { await tags.loadNotes() }
    }

    @ViewBuilder
    private var inspector: some View {
        if let document = workspace.selectedDocument {
            DocumentInspectorView(
                document: document,
                open: { workspace.open(path: $0) },
                showTag: showTag
            )
        } else {
            ContentUnavailableView("選んでいるファイルはありません", systemImage: "info.circle")
        }
    }
}

/// ツールバーの表示モード（ライブプレビュー／ソース／閲覧）の切り替え。
private struct DisplayModePicker: View {
    @Bindable var document: DocumentViewModel

    var body: some View {
        Picker("表示モード", selection: $document.displayMode) {
            ForEach(document.availableModes) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .help("表示モード（⌘E で編集と閲覧を切り替え）")
        .accessibilityIdentifier("display-mode-picker")
    }
}
