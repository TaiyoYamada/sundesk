//
//  VaultSettingsView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskComposition
import SwiftUI
import UniformTypeIdentifiers

/// Vault（ノートの入ったフォルダ）の場所。
struct VaultSettingsView: View {
    @AppStorage(VaultSettings.Key.directory) private var directory = ""
    @State private var isChoosing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("フォルダ") {
                    HStack {
                        TextField("フォルダ", text: $directory, prompt: Text(VaultSettings.defaultDirectory().path))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .truncationMode(.middle)
                        Button("選択…") { isChoosing = true }
                    }
                }
                Button("Finder で開く", systemImage: "folder") {
                    NSWorkspace.shared.open(VaultSettings.directory())
                }
                .buttonStyle(.link)
            } footer: {
                Text("空欄のときは、リポジトリにあるモックの SampleVault を使います。変更はアプリを再起動すると反映されます。sundesk は Vault のファイルを読むだけで、書き換えません。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { directory = url.path }
        }
    }
}

#Preview {
    VaultSettingsView()
        .frame(width: 560)
}
