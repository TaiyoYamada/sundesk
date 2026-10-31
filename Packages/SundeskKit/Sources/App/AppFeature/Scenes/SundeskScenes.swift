//
//  SundeskScenes.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import LibraryFeature
import SwiftUI

/// アプリのすべての画面（ライブラリ、PDF を読むウインドウ、設定）。アプリのターゲットはこれを表示するだけ。
public struct SundeskScenes: Scene {
    public init() {}

    public var body: some Scene {
        Window("sundesk", id: "library") {
            LibraryWindowView(dependencies: Container.shared.libraryDependencies())
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            InspectorCommands()
            LibraryCommands()
        }

        WindowGroup(id: LibraryWindowView.readerWindowID, for: UUID.self) { $referenceID in
            if let referenceID {
                ReaderWindowView(dependencies: Container.shared.libraryDependencies(), referenceID: referenceID)
                    .frame(minWidth: 720, minHeight: 520)
            }
        }
        .defaultSize(width: 1200, height: 900)

        Settings {
            SettingsView()
        }
    }
}
