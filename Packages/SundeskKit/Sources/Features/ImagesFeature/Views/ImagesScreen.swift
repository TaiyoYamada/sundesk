//
//  ImagesScreen.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SwiftUI

/// 画像生成のタブ。上でプロンプトと設定を決め、下に生成した画像を並べる。
/// 画像はダブルクリックか Space で大きく開き、2〜4 枚を選べば並べて比べられる。
public struct ImagesScreen: View {
    @Bindable private var viewModel: ImagesViewModel
    @AppStorage("images.thumbnailSize") private var thumbnailSize = 180.0
    @FocusState private var isGalleryFocused: Bool

    private static let thumbnailRange = 96.0...400.0

    public init(viewModel: ImagesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                controls
                Divider()
                if let progress = viewModel.progress {
                    GenerationStatusBar(progress: progress)
                    Divider()
                }
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    Divider()
                }
                galleryHeader
                Divider()
                gallery
            }
            if let image = viewModel.viewerImage {
                ImageViewer(viewModel: viewModel, image: image)
                    .transition(.opacity)
            } else if !viewModel.comparedImages.isEmpty {
                ImageCompareView(viewModel: viewModel, images: viewModel.comparedImages)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.viewerImageID == nil)
        .animation(.easeOut(duration: 0.15), value: viewModel.comparedImageIDs.isEmpty)
        .onChange(of: viewModel.viewerImageID == nil && viewModel.comparedImageIDs.isEmpty) { _, closed in
            // ビューアを閉じたら、キーボードの操作をギャラリーに戻す
            if closed { isGalleryFocused = true }
        }
        .confirmationDialog(
            viewModel.deletionTitle,
            isPresented: Binding(
                get: { !viewModel.pendingDeletion.isEmpty },
                set: { if !$0 { viewModel.cancelDeletion() } }),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                // ダイアログが閉じると尋ねていた画像が空になるので、先に受け取っておく
                let ids = viewModel.pendingDeletion
                Task { await viewModel.delete(ids) }
            }
            Button("キャンセル", role: .cancel) { viewModel.cancelDeletion() }
        } message: {
            Text("画像のファイルと記録を削除します。この操作は取り消せません。")
        }
        .task { await viewModel.load() }
        .task { await viewModel.observe() }
    }

    // MARK: - 入力

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                TextField("どんな画像にするか（英語のほうが通りやすい）", text: $viewModel.prompt, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("image-prompt")
                promptHistory
            }
            HStack(spacing: 14) {
                Picker("モデル", selection: $viewModel.modelID) {
                    ForEach(viewModel.models) { Text("\($0.name)（\($0.detail)）").tag($0.id) }
                }
                .frame(maxWidth: 320)
                Picker("縦横比", selection: $viewModel.aspectRatio) {
                    ForEach(ImageAspectRatio.allCases) { ratio in
                        Label(ratio.title, systemImage: ratio.symbol).tag(ratio)
                    }
                }
                .fixedSize()
                Picker("長い辺", selection: $viewModel.size) {
                    ForEach(ImagesViewModel.sizes, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                .fixedSize()
                .help("出来上がりは \(viewModel.dimensions.label)")
                Text(viewModel.dimensions.label)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            HStack(spacing: 14) {
                LabeledContent("ステップ") {
                    TextField("既定", value: $viewModel.steps, format: .number)
                        .frame(width: 56)
                        .textFieldStyle(.roundedBorder)
                }
                .help("空ならモデルの既定")
                LabeledContent("種") {
                    HStack(spacing: 4) {
                        TextField("毎回変える", value: $viewModel.seed, format: .number.grouping(.never))
                            .frame(width: 104)
                            .textFieldStyle(.roundedBorder)
                        Button("種を毎回変える", systemImage: "dice") { viewModel.seed = nil }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(viewModel.seed == nil)
                    }
                }
                .help("空なら毎回変える。同じ種なら同じ画像になる。何枚か作るときは 1 枚ごとに 1 ずつ足す")
                Stepper(value: $viewModel.count, in: ImagesViewModel.counts) {
                    Text("\(viewModel.count) 枚").monospacedDigit()
                }
                .fixedSize()
                .help("続けて作る枚数")
                Spacer()
                if viewModel.isGenerating {
                    Button("止める", systemImage: "stop.fill") { viewModel.cancel() }
                        .keyboardShortcut(".", modifiers: .command)
                        .help("生成を止める（⌘.）")
                } else {
                    Button(viewModel.count > 1 ? "\(viewModel.count) 枚を生成" : "生成", systemImage: "wand.and.stars") {
                        viewModel.generate()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canGenerate)
                    .help("生成（⌘↩）")
                }
            }
        }
        .padding(12)
    }

    private var promptHistory: some View {
        Menu {
            if viewModel.promptHistory.isEmpty {
                Text("まだありません")
            } else {
                ForEach(viewModel.promptHistory.prefix(30), id: \.self) { prompt in
                    Button(prompt.count > 80 ? String(prompt.prefix(80)) + "…" : prompt) {
                        viewModel.prompt = prompt
                    }
                }
            }
        } label: {
            Label("これまでのプロンプト", systemImage: "clock.arrow.circlepath")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("これまでのプロンプトから選ぶ")
    }

    // MARK: - ギャラリー

    private var galleryHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("プロンプトで絞り込む", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button("消す", systemImage: "xmark.circle.fill") { viewModel.searchText = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quinary))
            .frame(maxWidth: 260)
            Toggle(isOn: $viewModel.showsFavoritesOnly) {
                Label("お気に入り", systemImage: viewModel.showsFavoritesOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .help("お気に入りだけを見る")
            Spacer()
            Text(countLabel)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if viewModel.canCompare {
                Button("並べて比較", systemImage: "square.split.2x1") { viewModel.compareSelection() }
                    .help("選んだ \(viewModel.selection.count) 枚を並べて比べる")
            }
            HStack(spacing: 4) {
                Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
                Slider(value: $thumbnailSize, in: Self.thumbnailRange)
                    .frame(width: 110)
                    .help("サムネイルの大きさ（⌘+ ⌘-）")
                Image(systemName: "photo").font(.body).foregroundStyle(.secondary)
            }
            .background {
                if viewModel.viewerImageID == nil && viewModel.comparedImageIDs.isEmpty {
                    HiddenShortcut("+", modifiers: .command) { resizeThumbnails(by: 1.2) }
                    HiddenShortcut("=", modifiers: .command) { resizeThumbnails(by: 1.2) }
                    HiddenShortcut(";", modifiers: .command) { resizeThumbnails(by: 1.2) }
                    HiddenShortcut("-", modifiers: .command) { resizeThumbnails(by: 1 / 1.2) }
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var countLabel: String {
        let total =
            viewModel.visibleImages.count == viewModel.images.count
            ? "\(viewModel.images.count) 枚" : "\(viewModel.visibleImages.count) / \(viewModel.images.count) 枚"
        return viewModel.selection.isEmpty ? total : "\(total) · \(viewModel.selection.count) 枚を選択"
    }

    private func resizeThumbnails(by factor: Double) {
        thumbnailSize = min(max(thumbnailSize * factor, Self.thumbnailRange.lowerBound), Self.thumbnailRange.upperBound)
    }

    @ViewBuilder
    private var gallery: some View {
        if viewModel.images.isEmpty && viewModel.progress == nil {
            ContentUnavailableView(
                "まだ画像はありません", systemImage: "photo.on.rectangle.angled",
                description: Text("mflux で、手元の Mac だけで画像を作ります。初回はモデルのダウンロードに時間がかかります。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleImages.isEmpty && viewModel.progress == nil {
            ContentUnavailableView.search(text: viewModel.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ImageGalleryView(viewModel: viewModel, thumbnailSize: thumbnailSize, isFocused: $isGalleryFocused)
        }
    }
}

/// 生成の進み具合。何枚目か、何ステップ目か、仕上がりまでの見込み。
private struct GenerationStatusBar: View {
    let progress: ProgressItem

    var body: some View {
        HStack(spacing: 12) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction).frame(width: 160)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(progress.title).font(.callout)
                TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                    Text(
                        [
                            progress.detail, progress.remainingText(now: context.date),
                            progress.elapsedText(now: context.date),
                        ]
                        .compactMap(\.self)
                        .joined(separator: " · ")
                    )
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

extension ImageAspectRatio {
    /// メニューに添える形。
    fileprivate var symbol: String {
        switch self {
        case .square: "square"
        case .landscape4x3, .landscape3x2: "rectangle"
        case .portrait3x4, .portrait2x3: "rectangle.portrait"
        case .landscape16x9: "rectangle.ratio.16.to.9"
        case .portrait9x16: "rectangle.ratio.9.to.16"
        }
    }
}
