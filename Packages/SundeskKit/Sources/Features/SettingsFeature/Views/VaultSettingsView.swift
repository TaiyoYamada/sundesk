//
//  VaultSettingsView.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の「Vault」（ノートの入ったフォルダの場所）。
public struct VaultSettingsView: View {
    @Bindable private var settings: VaultSettingsViewModel
    @State private var isChoosing = false

    public init(settings: VaultSettingsViewModel) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent("フォルダ") {
                    HStack {
                        TextField("フォルダ", text: $settings.vaultDirectory, prompt: Text(settings.defaultVaultDirectory))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .truncationMode(.middle)
                        Button("選択…") { isChoosing = true }
                    }
                }
                Button("Finder で開く", systemImage: "folder") {
                    NSWorkspace.shared.open(settings.effectiveVaultURL)
                }
                .buttonStyle(.link)
            } footer: {
                Text("空欄のときは、リポジトリにあるモックの SampleVault を使います。変更はアプリを再起動すると反映されます。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { settings.vaultDirectory = url.path }
        }
    }
}
