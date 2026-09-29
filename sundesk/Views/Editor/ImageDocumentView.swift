//
//  ImageDocumentView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftUI

/// 画像を表示する。ピンチか下のボタンで拡大・縮小できる。
struct ImageDocumentView: View {
    let url: URL
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @State private var fitsWindow = true

    private var scale: CGFloat { zoom * gestureZoom }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: displayWidth(of: image, in: geometry.size),
                            height: displayWidth(of: image, in: geometry.size) * image.size.height
                                / max(image.size.width, 1)
                        )
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { gestureZoom = $0.magnification }
                        .onEnded { value in
                            zoom = min(max(zoom * value.magnification, 0.1), 8)
                            gestureZoom = 1
                        }
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("縮小", systemImage: "minus.magnifyingglass") { zoom = max(zoom / 1.25, 0.1) }
                Text(fitsWindow && zoom == 1 ? "ウインドウに合わせる" : "\(Int(scale * 100))%")
                    .monospacedDigit()
                    .frame(minWidth: 120)
                Button("拡大", systemImage: "plus.magnifyingglass") { zoom = min(zoom * 1.25, 8) }
                Divider().frame(height: 16)
                Button("合わせる", systemImage: "arrow.down.right.and.arrow.up.left") {
                    fitsWindow = true
                    zoom = 1
                }
                Button("実寸", systemImage: "1.magnifyingglass") {
                    fitsWindow = false
                    zoom = 1
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
            .background(.bar, in: .capsule)
            .padding(.bottom, 12)
        }
        .task(id: url) { image = NSImage(contentsOf: url) }
    }

    /// 「合わせる」ならウインドウに収まる幅、「実寸」なら画像の幅を基準に、拡大率を掛ける。
    private func displayWidth(of image: NSImage, in size: CGSize) -> CGFloat {
        let base: CGFloat =
            if fitsWindow {
                min(
                    image.size.width, size.width - 32, (size.height - 32) * image.size.width / max(image.size.height, 1)
                )
            } else {
                image.size.width
            }
        return max(base, 1) * scale
    }
}
