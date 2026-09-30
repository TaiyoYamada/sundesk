//
//  ZoomableImageView.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import SwiftUI

/// 拡大縮小の指示。同じ指示を続けて出せるよう、番号を付ける。
struct ZoomCommand: Equatable {
    enum Action: Equatable {
        case zoomIn
        case zoomOut
        /// 窓にぴったり収める。
        case fit
        /// 画像の 1 ピクセルを画面の 1 ピクセルで出す。
        case actualSize
    }

    let action: Action
    let token: Int
}

/// 画像を大きく見る。プレビューと同じく、ピンチ、スクロール、ダブルクリック（ぴったり ⇄ 等倍）で動かす。
struct ZoomableImageView: NSViewRepresentable {
    let url: URL
    let command: ZoomCommand?
    /// 倍率（1 = 等倍）が変わったとき。
    let onScaleChange: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 32
        let imageView = ZoomImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.onBackingChange = { [weak coordinator = context.coordinator] in
            coordinator?.backingDidChange()
        }
        imageView.onDoubleClick = { [weak coordinator = context.coordinator] point in
            coordinator?.toggleZoom(at: point)
        }
        scrollView.documentView = imageView
        context.coordinator.attach(scrollView, imageView: imageView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onScaleChange = onScaleChange
        if coordinator.url != url {
            coordinator.load(url)
        }
        if let command, command.token != coordinator.lastToken {
            coordinator.lastToken = command.token
            coordinator.apply(command.action)
        }
    }

    @MainActor
    final class Coordinator {
        var url: URL?
        var lastToken: Int?
        var onScaleChange: ((Double) -> Void)?
        private weak var scrollView: NSScrollView?
        private weak var imageView: ZoomImageView?
        /// ぴったり表示のままか。窓の大きさが変わったら合わせ直す。
        private var isFitting = true
        /// 1 ピクセルの大きさ（ポイント）。Retina なら 0.5。
        private var pointsPerPixel: CGFloat = 1
        private var reportedScale: Double?
        private var observers: [NSObjectProtocol] = []

        isolated deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(_ scrollView: NSScrollView, imageView: ZoomImageView) {
            self.scrollView = scrollView
            self.imageView = imageView
            scrollView.postsFrameChangedNotifications = true
            scrollView.contentView.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.isFitting = false
                        self?.report()
                    }
                },
                center.addObserver(
                    forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.isFitting else { return }
                        self.fit()
                    }
                },
                center.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                },
            ]
        }

        func load(_ url: URL) {
            self.url = url
            guard let imageView, let scrollView else { return }
            imageView.image = NSImage(contentsOf: url)
            isFitting = true
            resizeDocument()
        }

        /// 窓に入ったとき、Retina かどうかが変わったときに、画像の大きさ（ポイント）を測り直す。
        func backingDidChange() {
            let isFitting = isFitting
            resizeDocument()
            if !isFitting { report() }
        }

        /// 画像の 1 ピクセルが画面の 1 ピクセルになる大きさを、文書の大きさにする。
        private func resizeDocument() {
            guard let imageView, let scrollView else { return }
            let scale = scrollView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            pointsPerPixel = 1 / scale
            let image = imageView.image
            let pixels =
                image?.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
                ?? image?.size ?? .zero
            imageView.frame = CGRect(
                origin: .zero,
                size: CGSize(width: pixels.width * pointsPerPixel, height: pixels.height * pointsPerPixel))
            if isFitting { fit() }
        }

        func apply(_ action: ZoomCommand.Action) {
            guard let scrollView else { return }
            switch action {
            case .zoomIn:
                zoom(to: scrollView.magnification * 1.25)
            case .zoomOut:
                zoom(to: scrollView.magnification / 1.25)
            case .fit:
                isFitting = true
                fit()
            case .actualSize:
                zoom(to: 1)
            }
        }

        /// ダブルクリック: ぴったりなら等倍に（押したところを中心に）、そうでなければぴったりに戻す。
        func toggleZoom(at point: CGPoint) {
            guard let scrollView else { return }
            if isFitting {
                isFitting = false
                scrollView.setMagnification(1, centeredAt: point)
                report()
            } else {
                isFitting = true
                fit()
            }
        }

        private func zoom(to magnification: CGFloat) {
            guard let scrollView else { return }
            isFitting = false
            // 等倍の近くでは等倍に吸い付ける
            let target = abs(magnification - 1) < 0.06 ? 1 : magnification
            let visible = scrollView.documentVisibleRect
            scrollView.setMagnification(target, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
            report()
        }

        private func fit() {
            guard let scrollView, let imageView, imageView.frame.width > 0, imageView.frame.height > 0 else { return }
            let available = scrollView.contentSize
            guard available.width > 0, available.height > 0 else { return }
            let magnification = min(
                available.width / imageView.frame.width, available.height / imageView.frame.height)
            scrollView.magnification = min(max(magnification, scrollView.minMagnification), scrollView.maxMagnification)
            report()
        }

        private func report() {
            guard let scrollView else { return }
            let scale = Double(scrollView.magnification)
            guard reportedScale.map({ abs($0 - scale) > 0.001 }) ?? true else { return }
            reportedScale = scale
            let onScaleChange = onScaleChange
            // 画面を組み立てている途中に状態を変えないよう、次の周回で知らせる
            Task { @MainActor in onScaleChange?(scale) }
        }
    }
}

/// 画像が窓より小さいとき、まん中に置く。
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let frame = documentView.frame
        if rect.width > frame.width { rect.origin.x = (frame.width - rect.width) / 2 }
        if rect.height > frame.height { rect.origin.y = (frame.height - rect.height) / 2 }
        return rect
    }
}

/// キーボードの操作は SwiftUI の側で受けるので、選ばれる対象にならない画像の表示。
final class ZoomImageView: NSImageView {
    var onDoubleClick: ((CGPoint) -> Void)?
    var onBackingChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onBackingChange?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onBackingChange?()
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
        } else {
            super.mouseDown(with: event)
        }
    }
}
