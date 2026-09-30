//
//  ImageCompareView.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SwiftUI

/// 選んだ 2〜4 枚を並べて比べる（種やモデルを変えたときの違いを見る）。
struct ImageCompareView: View {
    @Bindable var viewModel: ImagesViewModel
    let images: [ImageItem]
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("ギャラリー", systemImage: "chevron.left") { viewModel.closeComparison() }
                    .buttonStyle(.borderless)
                    .help("ギャラリーに戻る（Esc）")
                Text("\(images.count) 枚を比較").font(.headline)
                Spacer()
                Text("ダブルクリックで大きく開きます").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            grid
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
        .background(.background)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.escape, .space]) { _ in
            viewModel.closeComparison()
            return .handled
        }
    }

    @ViewBuilder
    private var grid: some View {
        if images.count == 4 {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    cell(images[0])
                    cell(images[1])
                }
                GridRow {
                    cell(images[2])
                    cell(images[3])
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(images) { cell($0) }
            }
        }
    }

    private func cell(_ image: ImageItem) -> some View {
        VStack(spacing: 6) {
            ThumbnailImage(url: image.url, maxPixelSize: 2048)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    viewModel.closeComparison()
                    viewModel.openViewer(image.id)
                }
                .draggable(
                    DraggedImageFile(id: image.id, url: image.url, name: viewModel.suggestedFileName(for: image.id)))
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if image.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    Text(verbatim: "種 \(image.seed)").monospacedDigit()
                }
                .font(.callout.weight(.medium))
                Text(image.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(image.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(image.prompt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
