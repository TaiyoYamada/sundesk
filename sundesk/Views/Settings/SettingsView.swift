//
//  SettingsView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI

/// 「設定」ウインドウ（⌘,）。
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("エンジン", systemImage: "cpu") {
                EngineSettingsView()
            }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

#Preview {
    SettingsView()
}
