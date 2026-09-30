//
//  KnowledgeGraphView.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import MetalKit
import SwiftUI

/// 知識グラフを描く View。点、線、雲、文字をすべて Metal で描く。
///
/// ドラッグで移動（3 次元では回転、⌥ を押すと移動）、ピンチで拡大・縮小、2 本指のスクロールで移動、
/// 点のドラッグで置き直す。点を押すと選び、ダブルクリックでノートを開き、⇧ を押しながら押すと経路をたどる。
/// 矢印キーで隣へ移り、Esc で解除、Return でノートを開く。
public struct KnowledgeGraphView: View {
    private let model: GraphCanvasModel

    public init(model: GraphCanvasModel) {
        self.model = model
    }

    public var body: some View {
        if model.isAvailable {
            GraphMetalView(model: model)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("知識グラフ")
                .accessibilityIdentifier("knowledge-graph")
        } else {
            ContentUnavailableView("Metal を使えません", systemImage: "exclamationmark.triangle")
        }
    }
}

private struct GraphMetalView: NSViewRepresentable {
    let model: GraphCanvasModel

    func makeNSView(context: Context) -> GraphMTKView {
        let view = GraphMTKView(frame: .zero, device: model.renderer?.device)
        view.model = model
        model.view = view
        view.delegate = model.renderer
        view.colorPixelFormat = GraphPipelines.pixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.updateAppearance()
        return view
    }

    func updateNSView(_ view: GraphMTKView, context: Context) {
        view.model = model
    }
}
