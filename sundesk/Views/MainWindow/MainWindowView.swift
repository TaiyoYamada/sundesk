//
//  MainWindowView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskComposition
import SundeskPresentation
import SwiftUI

/// メインウインドウ。サイドバーで機能を切り替える。
struct MainWindowView: View {
    @SceneStorage("sidebar.selection") private var selection: SidebarDestination = .notes
    @InjectedObservable(\.engineStatusViewModel) private var engineStatus

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            DestinationPlaceholderView(destination: selection)
        }
        .navigationTitle(selection.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EngineStatusButton(viewModel: engineStatus)
            }
        }
        .task { await engineStatus.observe() }
    }
}

#Preview {
    MainWindowView()
        .frame(width: 900, height: 600)
}
