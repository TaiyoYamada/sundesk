//
//  EngineSettingsView.swift
//  EngineFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の「エンジン」。
public struct EngineSettingsView: View {
    @Bindable private var settings: EngineSettingsViewModel
    private let engineStatus: EngineStatusViewModel
    @State private var isChoosingDirectory = false
    @State private var isChoosingUV = false

    public init(settings: EngineSettingsViewModel, engineStatus: EngineStatusViewModel) {
        self.settings = settings
        self.engineStatus = engineStatus
    }

    public var body: some View {
        Form {
            Section {
                EngineStatusDetailView(viewModel: engineStatus)
            }

            Section {
                PathField(
                    title: "エンジンのフォルダ",
                    path: $settings.engineDirectory,
                    placeholder: settings.defaultEngineDirectory
                ) {
                    isChoosingDirectory = true
                }
                PathField(title: "uv の場所", path: $settings.uvExecutable, placeholder: settings.defaultUVExecutable) {
                    isChoosingUV = true
                }
            } header: {
                Text("場所")
            } footer: {
                Text("空欄のときは既定の場所を使います。変更は次にエンジンを起動したときに反映されます。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("アプリの起動時にエンジンを起動する", isOn: $settings.startsAutomatically)
            }
        }
        .formStyle(.grouped)
        .task { await engineStatus.observe() }
        .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { settings.engineDirectory = url.path }
        }
        .fileImporter(isPresented: $isChoosingUV, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case .success(let url) = result { settings.uvExecutable = url.path }
        }
    }
}

/// パスの入力欄と「選択…」ボタン。
private struct PathField: View {
    let title: String
    @Binding var path: String
    let placeholder: String
    let choose: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: $path, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .truncationMode(.middle)
                Button("選択…", action: choose)
            }
        }
    }
}
