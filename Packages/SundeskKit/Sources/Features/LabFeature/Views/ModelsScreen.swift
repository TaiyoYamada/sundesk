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
///
/// 一覧は Finder と同じく、⇧クリックと⌘クリックで複数選び、⌫ か右クリックでまとめて消せる。
public struct ModelsScreen: View {
    @Bindable private var viewModel: ModelsViewModel
    @State private var selection = Set<LocalModelItem.ID>()
    @State private var pendingDeletion: Set<LocalModelItem.ID>?

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
                if !selection.isEmpty {
                    Text("\(selection.count) 個を選択").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("選んだモデルを削除", systemImage: "trash") { requestDeletion(selection) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty)
                    .help("選んだモデルを削除（⌫）")
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
                Table(viewModel.models, selection: $selection) {
                    TableColumn("モデル", value: \.name)
                    TableColumn("種類", value: \.kind).width(min: 60, ideal: 80)
                    TableColumn("大きさ", value: \.size).width(min: 60, ideal: 80)
                }
                .contextMenu(forSelectionType: LocalModelItem.ID.self) { ids in
                    if !ids.isEmpty {
                        Button("Finder で表示") {
                            let urls = viewModel.models.filter { ids.contains($0.id) }.map { URL(filePath: $0.path) }
                            NSWorkspace.shared.activateFileViewerSelecting(urls)
                        }
                        Divider()
                        Button(ids.count == 1 ? "削除…" : "\(ids.count) 個を削除…", role: .destructive) {
                            requestDeletion(ids)
                        }
                    }
                }
                .onDeleteCommand { requestDeletion(selection) }
                .focusesOnClick()
                .onChange(of: viewModel.models) {
                    selection.formIntersection(viewModel.models.map(\.id))
                }
                .accessibilityIdentifier("local-models")
            }
        }
        .confirmsDeletion($pendingDeletion) { ids in
            DeletionTitle.make(
                count: ids.count, unit: "個", noun: "モデル",
                name: viewModel.models.first { ids.contains($0.id) }?.name)
        } delete: { ids in
            Task { await viewModel.delete(ids) }
        }
    }

    private func requestDeletion(_ ids: Set<LocalModelItem.ID>) {
        guard !ids.isEmpty else { return }
        pendingDeletion = ids
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
