//
//  ModelsScreen.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskDesignSystem
import SwiftUI

/// モデルのタブ。手元のモデルの一覧、Hugging Face からの取り込み、メモリの状態。
public struct ModelsScreen: View {
    @Bindable private var viewModel: ModelsViewModel

    public init(viewModel: ModelsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
                Divider()
            }
            HStack(alignment: .top, spacing: 0) {
                modelList
                Divider()
                sidePanel.frame(width: 320)
            }
        }
        .task { await viewModel.load() }
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("手元のモデル").font(.headline)
                Spacer()
                Button("読み直す", systemImage: "arrow.clockwise") { Task { await viewModel.load() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(12)
            if viewModel.models.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "モデルはまだありません", systemImage: "shippingbox",
                    description: Text("右から Hugging Face のモデルを取り込めます。エンジンが止まっていれば、起動してから一覧を読みます。"))
            } else {
                Table(viewModel.models) {
                    TableColumn("モデル", value: \.id)
                    TableColumn("種類", value: \.kind).width(min: 60, ideal: 80)
                    TableColumn("大きさ", value: \.size).width(min: 60, ideal: 80)
                }
                .contextMenu(forSelectionType: LocalModelItem.ID.self) { ids in
                    Button("Finder で表示") {
                        let urls = viewModel.models.filter { ids.contains($0.id) }.map { URL(filePath: $0.path) }
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                    }
                    Button("削除", role: .destructive) {
                        Task { for id in ids { await viewModel.delete(id) } }
                    }
                }
            }
        }
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorSection("取り込む") {
                    HStack {
                        TextField("mlx-community/…", text: $viewModel.downloadID)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.startDownload() }
                        Button("取り込む") { viewModel.startDownload() }
                            .disabled(viewModel.downloadID.isEmpty || viewModel.download != nil)
                    }
                    if let download = viewModel.download {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(download.id).font(.caption)
                            if let fraction = download.fraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            HStack {
                                Text(download.detail).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("止める") { viewModel.cancelDownload() }.controlSize(.small)
                            }
                        }
                    }
                }
                InspectorSection("おすすめ") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ModelsViewModel.suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(suggestion.id.split(separator: "/").last.map(String.init) ?? suggestion.id)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if viewModel.models.contains(where: { $0.id == suggestion.id }) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Button("取り込む") { viewModel.startDownload(suggestion.id) }
                                            .controlSize(.small)
                                            .disabled(viewModel.download != nil)
                                    }
                                }
                                Text(suggestion.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout)
                }
                InspectorSection("メモリに載っているもの") {
                    if let loaded = viewModel.loaded, !loaded.lines.isEmpty {
                        ForEach(loaded.lines, id: \.self) { Text($0).font(.callout) }
                        Button("すべて外す") { Task { await viewModel.unloadAll() } }
                            .controlSize(.small)
                    } else {
                        Text("なし").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }
}
