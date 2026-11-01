//
//  SettingsView.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import SettingsFeature
import SwiftUI

/// 「設定」ウインドウ（⌘,）。
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("一般", systemImage: "gearshape") {
                AppearanceSettingsView()
            }
            Tab("ライブラリ", systemImage: "books.vertical") {
                LibrarySettingsView(dataDirectory: Container.shared.dataDirectory())
            }
        }
        .frame(width: 560)
        .scenePadding()
    }
}
