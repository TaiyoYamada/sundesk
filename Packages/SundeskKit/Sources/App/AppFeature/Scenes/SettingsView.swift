//
//  SettingsView.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import FactoryKit
import SettingsFeature
import SwiftUI

/// 「設定」ウインドウ（⌘,）。各機能の設定の画面を、タブにまとめる。
struct SettingsView: View {
    @State private var vaultSettings = Container.shared.vaultSettingsViewModel()
    @State private var engineSettings = Container.shared.engineSettingsViewModel()

    var body: some View {
        TabView {
            Tab("一般", systemImage: "gearshape") {
                AppearanceSettingsView()
            }
            Tab("Vault", systemImage: "books.vertical") {
                VaultSettingsView(settings: vaultSettings)
            }
            Tab("エンジン", systemImage: "cpu") {
                EngineSettingsView(settings: engineSettings, engineStatus: Container.shared.engineStatusViewModel())
            }
        }
        .frame(width: 560)
        .scenePadding()
    }
}
