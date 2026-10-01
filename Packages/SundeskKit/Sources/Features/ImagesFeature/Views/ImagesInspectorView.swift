//
//  ImagesInspectorView.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskDesignSystem
import SwiftUI

/// 画像生成のインスペクタ。1 枚なら設定と操作、何枚かならまとめての操作。
public struct ImagesInspectorView: View {
    private let viewModel: ImagesViewModel

    public init(viewModel: ImagesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let image = viewModel.selectedImage {
            single(image)
        } else if !viewModel.selection.isEmpty {
            multiple(viewModel.selectedImages)
        } else {
            ContentUnavailableView(
                "画像を選んでください", systemImage: "photo",
                description: Text("選んだ画像の設定を表示します。⌘ や ⇧ を押しながらクリックすると、何枚か選べます。"))
        }
    }

    private func single(_ image: ImageItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ThumbnailImage(url: image.url, maxPixelSize: 600)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { viewModel.openViewer(image.id) }
                    .help("ダブルクリックで大きく開く")
                InspectorSection("プロンプト") {
                    Text(image.prompt).textSelection(.enabled).font(.callout)
                }
                InspectorSection("設定") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                        row("モデル", image.model)
                        row("大きさ", image.size)
                        row("ステップ", image.steps)
                        row("種", "\(image.seed)")
                        row("時間", image.seconds)
                        row("日時", image.date)
                    }
                    .font(.callout)
                }
                InspectorSection("この設定で") {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("同じ設定を使う", systemImage: "arrow.uturn.backward") {
                            viewModel.reuseSettings(of: image.id)
                        }
                        .help("プロンプトと設定を、上の入力に戻す")
                        Button("種だけ変えてもう一度生成", systemImage: "dice") {
                            viewModel.regenerate(from: image.id)
                        }
                        .disabled(viewModel.isGenerating)
                        Button("同じ種でもう一度生成", systemImage: "arrow.clockwise") {
                            viewModel.regenerate(from: image.id, keepingSeed: true)
                        }
                        .disabled(viewModel.isGenerating)
                        .help("同じ種なら同じ画像になります。ステップやモデルを変えて比べるときに")
                    }
                }
                InspectorSection("ファイル") {
                    fileActions([image.id])
                }
            }
            .controlSize(.small)
            .padding(14)
        }
    }

    private func multiple(_ images: [ImageItem]) -> some View {
        let ids = images.map(\.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 6) {
                    ForEach(images.prefix(24)) { image in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { ThumbnailImage(url: image.url, maxPixelSize: 128) }
                    }
                }
                InspectorSection("\(images.count) 枚を選択") {
                    VStack(alignment: .leading, spacing: 6) {
                        if viewModel.canCompare {
                            Button("並べて比較", systemImage: "square.split.2x1") { viewModel.compareSelection() }
                        }
                        Button(
                            viewModel.isFavorite(ids) ? "お気に入りから外す" : "お気に入りにする",
                            systemImage: viewModel.isFavorite(ids) ? "star.slash" : "star"
                        ) {
                            Task { await viewModel.toggleFavorite(ids) }
                        }
                    }
                }
                InspectorSection("ファイル") {
                    fileActions(ids)
                }
            }
            .controlSize(.small)
            .padding(14)
        }
    }

    private func fileActions(_ ids: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if ids.count == 1, let id = ids.first {
                Button("大きく開く", systemImage: "arrow.up.left.and.arrow.down.right") { viewModel.openViewer(id) }
            }
            Button("コピー", systemImage: "doc.on.doc") { ImageFileActions.copy(viewModel.urls(for: ids)) }
            Button("書き出す…", systemImage: "square.and.arrow.up") { ImageFileActions.export(ids, viewModel: viewModel) }
            Button("Finder で表示", systemImage: "folder") { ImageFileActions.reveal(viewModel.urls(for: ids)) }
            Button(ids.count == 1 ? "削除…" : "\(ids.count) 枚を削除…", systemImage: "trash", role: .destructive) {
                viewModel.requestDelete(ids)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
