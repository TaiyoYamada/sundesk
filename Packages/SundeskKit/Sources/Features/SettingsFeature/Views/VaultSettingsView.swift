//
//  VaultSettingsView.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の「ライブラリ」（研究の一次資料の置き場所）。
public struct VaultSettingsView: View {
    @Bindable private var settings: VaultSettingsViewModel
    @State private var choosing: Choice?
    @State private var restoreSource: URL?

    private enum Choice {
        case export, restore
    }

    public init(settings: VaultSettingsViewModel) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent("場所") {
                    Text(settings.libraryPath).textSelection(.enabled).truncationMode(.middle).lineLimit(1)
                }
                Button("Finder で開く", systemImage: "folder") {
                    NSWorkspace.shared.open(settings.effectiveVaultURL)
                }
                .buttonStyle(.link)
            } footer: {
                Text("論文、実験、データ、資料、ノートは、アプリの中のこのフォルダに置きます。Time Machine の対象に含まれます。")
                    .foregroundStyle(.secondary)
            }
            Section("書き出しと戻し") {
                Button("ライブラリを書き出す…") { choosing = .export }
                Button("書き出したものから戻す…") { choosing = .restore }
                if settings.isWorking { ProgressView().controlSize(.small) }
                if let message = settings.message {
                    Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section {
                Toggle("見本のライブラリで試す", isOn: $settings.usesSampleLibrary)
            } footer: {
                Text("リポジトリにある研究向けの見本（SampleLibrary）を開きます。開発や動作の確認に使います。")
                    .foregroundStyle(.secondary)
            }
            if settings.needsRestart {
                Label("アプリを再起動すると反映されます", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            switch choosing {
            case .export: Task { await settings.export(into: url) }
            case .restore: restoreSource = url
            case nil: break
            }
            choosing = nil
        }
        .confirmationDialog(
            "ライブラリを置き換えますか？",
            isPresented: Binding(get: { restoreSource != nil }, set: { if !$0 { restoreSource = nil } })
        ) {
            Button("置き換える", role: .destructive) {
                if let source = restoreSource { Task { await settings.restore(from: source) } }
                restoreSource = nil
            }
        } message: {
            Text("今のライブラリは消さずに、日付を付けて横に残します。")
        }
    }
}
