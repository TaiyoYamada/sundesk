//
//  SundeskScenes.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import SwiftUI
import WorkspaceFeature

/// アプリのすべての画面（メインウインドウ、設定）。アプリのターゲットはこれを表示するだけ。
public struct SundeskScenes: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup("sundesk", id: "main") {
            MainWindowView(dependencies: Container.shared.workspaceDependencies())
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            WorkspaceCommands()
            EngineCommands(engineStatus: Container.shared.engineStatusViewModel())
        }

        Settings {
            SettingsView()
        }
    }
}
