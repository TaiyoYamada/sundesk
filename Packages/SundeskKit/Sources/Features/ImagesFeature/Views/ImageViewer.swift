//
//  ImageViewer.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SwiftUI

/// 画像を大きく見る（写真アプリで開いたとき、Quick Look と同じ操作）。
///
/// ← → で前後の画像、Esc か Space で閉じる。⌘+ ⌘- で拡大縮小、⌘0 でぴったり、ダブルクリックでぴったり ⇄ 等倍。
struct ImageViewer: View {
    @Bindable var viewModel: ImagesViewModel
    let image: ImageItem
    @State private var command: ZoomCommand?
    @State private var scale = 1.0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZoomableImageView(url: image.url, command: command) { scale = $0 }
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            caption
        }
        .background(.background)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) {
            viewModel.showAdjacent(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.showAdjacent(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.showAdjacent(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.showAdjacent(1)
            return .handled
        }
        .onKeyPress(keys: [.escape, .space]) { _ in
            viewModel.closeViewer()
            return .handled
        }
        .onKeyPress(characters: ["."]) { _ in
            Task { await viewModel.toggleFavorite([image.id]) }
            return .handled
        }
        .onDeleteCommand { viewModel.requestDelete([image.id]) }
        .onCommand(#selector(NSText.copy(_:))) { ImageFileActions.copy([image.url]) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("ギャラリー", systemImage: "chevron.left") { viewModel.closeViewer() }
                .help("ギャラリーに戻る（Esc）")
            ControlGroup {
                Button("前の画像", systemImage: "chevron.backward") { viewModel.showAdjacent(-1) }
                    .disabled(!viewModel.canShowPrevious)
                    .help("前の画像（←）")
                Button("次の画像", systemImage: "chevron.forward") { viewModel.showAdjacent(1) }
                    .disabled(!viewModel.canShowNext)
                    .help("次の画像（→）")
            }
            .labelStyle(.iconOnly)
            .fixedSize()
            if let position = viewModel.viewerPosition {
                Text(position).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            zoomControls
            Divider().frame(height: 18)
            imageActions
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button("縮小", systemImage: "minus.magnifyingglass") { send(.zoomOut) }
                .keyboardShortcut("-", modifiers: .command)
                .help("縮小（⌘-）")
            Text("\(Int((scale * 100).rounded()))%")
                .monospacedDigit()
                .frame(minWidth: 44)
                .foregroundStyle(.secondary)
            Button("拡大", systemImage: "plus.magnifyingglass") { send(.zoomIn) }
                .keyboardShortcut("+", modifiers: .command)
                .help("拡大（⌘+）")
            Button("ぴったり表示", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { send(.fit) }
                .keyboardShortcut("0", modifiers: .command)
                .help("窓にぴったり収める（⌘0）")
            Button("等倍", systemImage: "1.magnifyingglass") { send(.actualSize) }
                .help("画像の 1 ピクセルを画面の 1 ピクセルで見る（ダブルクリックでも切り替わります）")
        }
        .labelStyle(.iconOnly)
        .background {
            // 配列の違うキーボードでも ⌘+ が効くように、⌘= と ⌘; も受ける
            HiddenShortcut("=", modifiers: .command) { send(.zoomIn) }
            HiddenShortcut(";", modifiers: .command) { send(.zoomIn) }
        }
    }

    private var imageActions: some View {
        HStack(spacing: 8) {
            Button(
                image.isFavorite ? "お気に入りから外す" : "お気に入りにする",
                systemImage: image.isFavorite ? "star.fill" : "star"
            ) {
                Task { await viewModel.toggleFavorite([image.id]) }
            }
            .foregroundStyle(image.isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.primary))
            .help("お気に入り（.）")
            Button("コピー", systemImage: "doc.on.doc") { ImageFileActions.copy([image.url]) }
                .help("クリップボードへコピー（⌘C）")
            Button("書き出す", systemImage: "square.and.arrow.up") {
                ImageFileActions.export([image.id], viewModel: viewModel)
            }
            .help("書き出す")
            Button("Finder で表示", systemImage: "folder") { ImageFileActions.reveal([image.url]) }
                .help("Finder で表示")
            Button("削除", systemImage: "trash") { viewModel.requestDelete([image.id]) }
                .help("削除（⌫）")
        }
        .labelStyle(.iconOnly)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(image.prompt)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(image.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ action: ZoomCommand.Action) {
        command = ZoomCommand(action: action, token: (command?.token ?? 0) + 1)
    }
}

/// 見えないが、キーボードショートカットだけ効くボタン（別の配列のキーを足すのに使う）。
struct HiddenShortcut: View {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    init(_ key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    var body: some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
