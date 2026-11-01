//
//  SundeskScenes.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import LibraryFeature
import SwiftUI

/// アプリのすべての画面（ライブラリ、設定）。アプリのターゲットはこれを表示するだけ。
public struct SundeskScenes: Scene {
    public init() {}

    public var body: some Scene {
        Window("sundesk", id: "library") {
            LibraryWindowView(dependencies: Container.shared.libraryDependencies())
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        // 前回ウインドウを閉じたまま終了していても、起動したらライブラリを出す（ほかに開くウインドウがないため）
        .defaultLaunchBehavior(.presented)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            InspectorCommands()
            LibraryCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
