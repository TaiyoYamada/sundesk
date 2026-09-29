//
//  ImagesScreen.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskDesignSystem
import SwiftUI

/// 画像生成のタブ。上でプロンプトと設定を決め、下に生成した画像を並べる。
public struct ImagesScreen: View {
    @Bindable private var viewModel: ImagesViewModel

    public init(viewModel: ImagesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if let progress = viewModel.progress {
                ProgressBanner(title: progress.title, fraction: progress.fraction)
                Divider()
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
                Divider()
            }
            gallery
        }
        .task { await viewModel.load() }
        .task { await viewModel.observe() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("どんな画像にするか（英語のほうが通りやすい）", text: $viewModel.prompt, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("image-prompt")
            HStack(spacing: 14) {
                Picker("モデル", selection: $viewModel.modelID) {
                    ForEach(viewModel.models) { Text("\($0.name)（\($0.detail)）").tag($0.id) }
                }
                .frame(maxWidth: 360)
                Picker("大きさ", selection: $viewModel.size) {
                    ForEach(ImagesViewModel.sizes, id: \.self) { Text("\($0)").tag($0) }
                }
                .fixedSize()
                TextField("ステップ", value: $viewModel.steps, format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .help("空ならモデルの既定")
                TextField("種", value: $viewModel.seed, format: .number)
                    .frame(width: 90)
                    .textFieldStyle(.roundedBorder)
                    .help("空なら毎回変える。同じ種なら同じ画像になる")
                Spacer()
                if viewModel.isGenerating {
                    Button("止める", systemImage: "stop.fill") { viewModel.cancel() }
                } else {
                    Button("生成", systemImage: "wand.and.stars") { viewModel.generate() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canGenerate)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var gallery: some View {
        if viewModel.images.isEmpty {
            ContentUnavailableView(
                "まだ画像はありません", systemImage: "photo.on.rectangle.angled",
                description: Text("mflux で、手元の Mac だけで画像を作ります。初回はモデルのダウンロードに時間がかかります。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.images) { image in
                        GalleryImage(image: image, isSelected: viewModel.selectedImageID == image.id)
                            .onTapGesture { viewModel.selectedImageID = image.id }
                            .contextMenu {
                                Button("同じ設定を使う") { viewModel.reuseSettings(of: image.id) }
                                Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
                                Divider()
                                Button("削除", role: .destructive) { Task { await viewModel.delete(image.id) } }
                            }
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct GalleryImage: View {
    let image: ImageItem
    let isSelected: Bool
    @State private var loaded: NSImage?

    var body: some View {
        ZStack {
            if let loaded {
                Image(nsImage: loaded).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(minWidth: 180, minHeight: 180)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
        )
        .task(id: image.url) { loaded = NSImage(contentsOf: image.url) }
        .help(image.prompt)
        .accessibilityLabel(image.prompt)
    }
}

/// 画像生成のインスペクタ。選んだ画像の設定。
public struct ImagesInspectorView: View {
    private let viewModel: ImagesViewModel

    public init(viewModel: ImagesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let image = viewModel.selectedImage {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                        HStack {
                            Button("同じ設定を使う") { viewModel.reuseSettings(of: image.id) }
                            Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(14)
            }
        } else {
            ContentUnavailableView("画像を選んでください", systemImage: "photo", description: Text("選んだ画像の設定を表示します。"))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
