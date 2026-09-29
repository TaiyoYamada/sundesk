//
//  MainWindowView.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import ChatFeature
import EngineFeature
import GraphFeature
import ImagesFeature
import LabFeature
import LibraryFeature
import NotesFeature
import SwiftUI

/// メインウインドウ。左にナビゲータ、中央にタブのエディタ、右にインスペクタを置く（ADR 0009）。
public struct MainWindowView: View {
    private let dependencies: WorkspaceDependencies
    @State private var workspace: WorkspaceViewModel
    @State private var search: SearchViewModel
    @State private var tags: TagsViewModel
    @State private var graph: GraphViewModel
    @State private var chat: ChatViewModel
    @State private var tools: ToolViewModels
    @State private var cache = DocumentViewCache()
    @State private var library: LibraryViewModel
    @State private var screens: LibraryScreenCache

    public init(dependencies: WorkspaceDependencies) {
        self.dependencies = dependencies
        _workspace = State(initialValue: dependencies.makeWorkspace())
        _search = State(initialValue: dependencies.makeSearch())
        _tags = State(initialValue: dependencies.makeTags())
        _graph = State(initialValue: dependencies.makeGraph())
        _chat = State(initialValue: dependencies.makeChat())
        _library = State(initialValue: dependencies.makeLibrary())
        _screens = State(initialValue: LibraryScreenCache(dependencies: dependencies))
        _tools = State(
            initialValue: ToolViewModels(
                lab: dependencies.makeLab(), forge: dependencies.makeForge(), scratch: dependencies.makeScratch(),
                models: dependencies.makeModels(), images: dependencies.makeImages()))
    }

    public var body: some View {
        NavigationSplitView {
            NavigatorView(
                workspace: workspace, navigator: dependencies.fileNavigator, search: search, tags: tags,
                library: library
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            EditorView(
                workspace: workspace, cache: cache, screens: screens, graph: graph, chat: chat, tools: tools,
                showTag: showTag)
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
        .task { await graph.observe() }
        .task { await graph.observeBuildProgress() }
        .task { await chat.observe() }
        .task { await chat.observeBuildProgress() }
    }

    /// タグのノートの一覧を、ナビゲータに出す。
    private func showTag(_ name: String) {
        workspace.navigatorMode = .tags
        tags.selectedTag = name
        Task { await tags.loadNotes() }
    }

    @ViewBuilder
    private var inspector: some View {
        if workspace.selectedTab?.content == .tool(.graph) {
            GraphInspectorView(viewModel: graph) { path, line in workspace.open(path: path, line: line) }
        } else if workspace.selectedTab?.content == .tool(.chat) {
            ChatInspectorView(viewModel: chat) { path, line in workspace.open(path: path, line: line) }
        } else if workspace.selectedTab?.content == .tool(.images) {
            ImagesInspectorView(viewModel: tools.images)
        } else if let document = workspace.selectedDocument {
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
