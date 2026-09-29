//
//  AppearanceSettingsView.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftUI

/// アプリの見た目（システムに合わせる、ライト、ダーク）。
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: Self { self }

    /// 保存する UserDefaults のキー。
    public static let storageKey = "appearance"

    public var title: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// 保存してある見た目。
    public static var stored: AppAppearance {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppAppearance.init) ?? .system
    }

    /// アプリ全体（AppKit のエディタやメニューを含む）に反映する。
    @MainActor
    public func apply() {
        NSApp.appearance =
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
    }
}

/// 設定の「一般」。
public struct AppearanceSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    public init() {}

    public var body: some View {
        Form {
            Picker("外観", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
            Text("「システム」なら、Mac の設定（ライトとダークの切り替え）に合わせます。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onChange(of: appearance, initial: true) { _, value in value.apply() }
    }
}
