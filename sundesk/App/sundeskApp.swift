//
//  sundeskApp.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskComposition
import SundeskPresentation
import SwiftUI

@main
struct SundeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @InjectedObservable(\.engineStatusViewModel) private var engineStatus

    var body: some Scene {
        WindowGroup("sundesk", id: "main") {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            WorkspaceCommands()
            EngineCommands(engineStatus: engineStatus)
        }

        Settings {
            SettingsView()
        }
    }
}
