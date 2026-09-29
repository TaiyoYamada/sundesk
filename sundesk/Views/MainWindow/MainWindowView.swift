//
//  MainWindowView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskComposition
import SundeskPresentation
import SwiftUI

/// メインウインドウ。左にナビゲータ、中央にタブのエディタ、右にインスペクタを置く（Xcode や Obsidian と同じ構成）。
struct MainWindowView: View {
    @State private var workspace = Container.shared.workspaceViewModel()
    @State private var pages = RenderedPageCache()
    @InjectedObservable(\.fileNavigatorViewModel) private var navigator
    @InjectedObservable(\.engineStatusViewModel) private var engineStatus

    var body: some View {
        NavigationSplitView {
            NavigatorView(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
        } detail: {
            EditorView(workspace: workspace, pages: pages)
        }
        .inspector(isPresented: $workspace.isInspectorPresented) {
            InspectorView(workspace: workspace, pages: pages)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 380)
        }
        .navigationTitle(workspace.selectedTab?.title ?? navigator.vaultName)
        .navigationSubtitle(workspace.selectedTab == nil ? "" : navigator.vaultName)
        .toolbar {
            if let document = workspace.selectedDocument, document.canToggleDisplayMode {
                ToolbarItem(placement: .primaryAction) {
                    DisplayModePicker(document: document)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                EngineStatusButton(viewModel: engineStatus)
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
            pages.keepOnly(paths: Set(tabs.compactMap(\.documentPath)))
        }
        .task { await engineStatus.observe() }
        .task { await navigator.observe() }
    }
}

/// ツールバーの「表示／ソース」の切り替え。
private struct DisplayModePicker: View {
    @Bindable var document: DocumentViewModel

    var body: some View {
        Picker("表示の切り替え", selection: $document.displayMode) {
            ForEach(DocumentViewModel.DisplayMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .help("表示とソースを切り替え（⌘E）")
        .accessibilityIdentifier("display-mode-picker")
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1100, height: 700)
}
