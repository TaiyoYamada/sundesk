//
//  WorkspaceCommands.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

/// タブ、表示の切り替え、ナビゲータのメニューとショートカット。いちばん手前のウインドウに効く。
struct WorkspaceCommands: Commands {
    @FocusedValue(WorkspaceViewModel.self) private var workspace

    var body: some Commands {
        CommandGroup(before: .saveItem) {
            Button("タブを閉じる") { workspace?.closeSelectedTab() }
                .keyboardShortcut("w")
                .disabled(workspace?.selectedTab == nil)
            Divider()
        }

        CommandGroup(before: .sidebar) {
            Button("表示とソースを切り替え") { workspace?.selectedDocument?.toggleDisplayMode() }
                .keyboardShortcut("e")
                .disabled(workspace?.selectedDocument?.canToggleDisplayMode != true)
            Button(workspace?.isInspectorPresented == true ? "インスペクタを隠す" : "インスペクタを表示") {
                workspace?.isInspectorPresented.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("移動") {
            ForEach(Array(WorkspaceViewModel.NavigatorMode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.title) { workspace?.navigatorMode = mode }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Button("ノートを検索") { workspace?.navigatorMode = .search }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("次のタブ") { workspace?.selectAdjacentTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("前のタブ") { workspace?.selectAdjacentTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
