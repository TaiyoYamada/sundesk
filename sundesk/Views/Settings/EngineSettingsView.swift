//
//  EngineSettingsView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskComposition
import SundeskPresentation
import SwiftUI
import UniformTypeIdentifiers

struct EngineSettingsView: View {
    @InjectedObservable(\.engineStatusViewModel) private var engineStatus

    @AppStorage(EngineSettings.Key.engineDirectory) private var engineDirectory = ""
    @AppStorage(EngineSettings.Key.uvExecutable) private var uvExecutable = ""
    @AppStorage(EngineSettings.Key.startsAutomatically) private var startsAutomatically = true

    @State private var isChoosingDirectory = false
    @State private var isChoosingUV = false

    var body: some View {
        Form {
            Section {
                EngineStatusDetailView(viewModel: engineStatus)
            }

            Section {
                PathField(
                    title: "エンジンのフォルダ",
                    path: $engineDirectory,
                    placeholder: EngineSettings.defaultEngineDirectory
                ) {
                    isChoosingDirectory = true
                }
                PathField(
                    title: "uv の場所",
                    path: $uvExecutable,
                    placeholder: EngineSettings.defaultUVExecutable
                ) {
                    isChoosingUV = true
                }
            } header: {
                Text("場所")
            } footer: {
                Text("空欄のときは既定の場所を使います。変更は次にエンジンを起動したときに反映されます。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("アプリの起動時にエンジンを起動する", isOn: $startsAutomatically)
            }
        }
        .formStyle(.grouped)
        .task { await engineStatus.observe() }
        .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { engineDirectory = url.path }
        }
        .fileImporter(isPresented: $isChoosingUV, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case .success(let url) = result { uvExecutable = url.path }
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

#Preview {
    EngineSettingsView()
        .frame(width: 560)
}
