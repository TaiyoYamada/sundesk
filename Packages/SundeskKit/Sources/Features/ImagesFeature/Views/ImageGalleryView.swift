//
//  ImageGalleryView.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import SwiftUI

/// 生成した画像の格子。Finder と同じく、クリック、⌘クリック、⇧クリック、⌘A で選び、⌫ でまとめて消す。
struct ImageGalleryView: View {
    @Bindable var viewModel: ImagesViewModel
    /// サムネイルの一辺。
    let thumbnailSize: Double
    @FocusState.Binding var isFocused: Bool
    @State private var width: CGFloat = 0

    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 12

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: Self.spacing)],
                    spacing: Self.spacing
                ) {
                    if let progress = viewModel.progress {
                        GeneratingTile(progress: progress)
                    }
                    ForEach(viewModel.visibleImages) { image in
                        tile(image)
                            .id(image.id)
                    }
                }
                .padding(Self.padding)
                .dragContainer(for: DraggedImageFile.self) { ids in
                    ids.compactMap { id in
                        viewModel.image(for: id).map {
                            DraggedImageFile(id: id, url: $0.url, name: viewModel.suggestedFileName(for: id))
                        }
                    }
                }
                .dragContainerSelection(viewModel.orderedSelection)
            }
            .background {
                // 何もないところをクリックしたら、選択を外す
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.clearSelection()
                        isFocused = true
                    }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .onChange(of: viewModel.focusedImageID) { _, id in
                guard let id, viewModel.viewerImageID == nil else { return }
                proxy.scrollTo(id)
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                viewModel.openViewer()
                return .handled
            }
            .onMoveCommand { direction in
                let extending = NSEvent.modifierFlags.contains(.shift)
                switch direction {
                case .left: viewModel.moveSelection(by: -1, extending: extending)
                case .right: viewModel.moveSelection(by: 1, extending: extending)
                case .up: viewModel.moveSelection(by: -columns, extending: extending)
                case .down: viewModel.moveSelection(by: columns, extending: extending)
                @unknown default: break
                }
            }
            .onKeyPress(characters: ["."]) { _ in
                Task { await viewModel.toggleFavorite() }
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                viewModel.requestDelete()
                return .handled
            }
            .onDeleteCommand { viewModel.requestDelete() }
            .onCommand(#selector(NSResponder.selectAll(_:))) { viewModel.selectAll() }
            .onCommand(#selector(NSText.copy(_:))) {
                ImageFileActions.copy(viewModel.urls(for: viewModel.orderedSelection))
            }
        }
    }

    /// 1 行に並ぶ数（上下の矢印で動く幅）。`GridItem.adaptive` と同じ数え方。
    private var columns: Int {
        max(1, Int((width - Self.padding * 2 + Self.spacing) / (thumbnailSize + Self.spacing)))
    }

    private func tile(_ image: ImageItem) -> some View {
        GalleryTile(image: image, isSelected: viewModel.isSelected(image.id), side: thumbnailSize)
            .draggable(containerItemID: image.id)
            .onTapGesture(count: 2) {
                viewModel.openViewer(image.id)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    viewModel.select(image.id, modifier: currentSelectionModifier())
                    isFocused = true
                }
            )
            .contextMenu { ImageContextMenu(viewModel: viewModel, ids: viewModel.targets(for: image.id)) }
    }
}

/// ギャラリーの 1 枚。
private struct GalleryTile: View {
    let image: ImageItem
    let isSelected: Bool
    let side: Double

    var body: some View {
        // 縦長も横長も、同じ正方形の枠に収めて並べる
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { ThumbnailImage(url: image.url, maxPixelSize: side * 2).padding(6) }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quinary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
            )
            .overlay(alignment: .bottomLeading) {
                if image.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.5), radius: 1.5)
                        .padding(8)
                        .accessibilityLabel("お気に入り")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .help(image.prompt)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(image.prompt)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 生成している途中の 1 枚（仕上がる大きさの枠に、進み具合を出す）。
private struct GeneratingTile: View {
    let progress: ProgressItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .aspectRatio(CGFloat(progress.width) / CGFloat(max(progress.height, 1)), contentMode: .fit)
                .padding(4)
            VStack(spacing: 6) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction).progressViewStyle(.circular)
                } else {
                    ProgressView()
                }
                Text(progress.detail ?? progress.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("生成しています")
    }
}

/// 画像の右クリックのメニュー。選んでいる画像を右クリックしたら、選んでいるすべてが相手。
struct ImageContextMenu: View {
    let viewModel: ImagesViewModel
    let ids: [UUID]

    var body: some View {
        let single = ids.count == 1 ? ids.first : nil
        if let single {
            Button("開く") { viewModel.openViewer(single) }
        } else if ImagesViewModel.comparableCount.contains(ids.count) {
            // 複数が相手になるのは、選んでいる画像を右クリックしたときだけ
            Button("\(ids.count) 枚を並べて比較") { viewModel.compareSelection() }
        }
        Button(viewModel.isFavorite(ids) ? "お気に入りから外す" : "お気に入りにする") {
            Task { await viewModel.toggleFavorite(ids) }
        }
        if let single {
            Divider()
            Button("同じ設定を使う") { viewModel.reuseSettings(of: single) }
            Button("種だけ変えてもう一度生成") { viewModel.regenerate(from: single) }
                .disabled(viewModel.isGenerating)
        }
        Divider()
        Button(ids.count == 1 ? "コピー" : "\(ids.count) 枚をコピー") {
            ImageFileActions.copy(viewModel.urls(for: ids))
        }
        Button(ids.count == 1 ? "書き出す…" : "\(ids.count) 枚を書き出す…") {
            ImageFileActions.export(ids, viewModel: viewModel)
        }
        Button("Finder で表示") { ImageFileActions.reveal(viewModel.urls(for: ids)) }
        Divider()
        Button(ids.count == 1 ? "削除…" : "\(ids.count) 枚を削除…", role: .destructive) {
            viewModel.requestDelete(ids)
        }
    }
}
