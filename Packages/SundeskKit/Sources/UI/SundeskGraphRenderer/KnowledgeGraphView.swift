//
//  KnowledgeGraphView.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import MetalKit
import SwiftUI

/// 知識グラフを描く View。点と線は Metal、ラベルは SwiftUI で重ねる。
///
/// ドラッグで移動、スクロールかピンチで拡大・縮小、点をドラッグすると動かせる。
public struct KnowledgeGraphView: View {
    private let model: GraphCanvasModel

    public init(model: GraphCanvasModel) {
        self.model = model
    }

    public var body: some View {
        if model.isAvailable {
            ZStack {
                GraphMetalView(model: model)
                GraphLabelsView(model: model)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("知識グラフ")
            .accessibilityIdentifier("knowledge-graph")
        } else {
            ContentUnavailableView("Metal を使えません", systemImage: "exclamationmark.triangle")
        }
    }
}

/// ラベル。描画のたびに位置を読み直す。
private struct GraphLabelsView: View {
    let model: GraphCanvasModel

    var body: some View {
        Canvas { context, _ in
            for label in model.labels() {
                let text = Text(label.text)
                    .font(
                        .system(size: label.isEmphasized ? 12 : 11, weight: label.isEmphasized ? .semibold : .regular)
                    )
                    .foregroundStyle(label.isEmphasized ? .primary : .secondary)
                context.draw(text, at: label.point, anchor: .center)
            }
        }
    }
}

private struct GraphMetalView: NSViewRepresentable {
    let model: GraphCanvasModel

    func makeNSView(context: Context) -> GraphMTKView {
        let view = GraphMTKView(frame: .zero, device: model.renderer?.device)
        view.model = model
        view.delegate = model.renderer
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.updateClearColor()
        return view
    }

    func updateNSView(_ view: GraphMTKView, context: Context) {
        view.model = model
    }
}

/// マウスとトラックパッドの操作を受ける MTKView。
final class GraphMTKView: MTKView {
    weak var model: GraphCanvasModel?
    private var draggingNode: Int?
    private var dragStart: CGPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        model?.viewSize = newSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateClearColor()
    }

    func updateClearColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var color = NSColor.textBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .white
        }
        clearColor = MTLClearColor(
            red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent),
            alpha: 1)
        model?.setAppearance(isDark: isDark)
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = location(of: event)
        dragStart = point
        didDrag = false
        draggingNode = model?.hitTest(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let point = location(of: event)
        if let start = dragStart, hypot(point.x - start.x, point.y - start.y) > 3 { didDrag = true }
        guard didDrag else { return }
        if let draggingNode {
            model.drag(node: draggingNode, to: point)
        } else {
            model.pan(by: CGSize(width: event.deltaX, height: -event.deltaY))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        if let draggingNode {
            model.release(node: draggingNode)
        }
        if !didDrag {
            model.click(at: location(of: event))
        }
        draggingNode = nil
        dragStart = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let model else { return }
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // トラックパッドの 2 本指は移動
            model.pan(by: CGSize(width: -event.scrollingDeltaX, height: event.scrollingDeltaY))
        } else {
            model.zoom(
                by: pow(1.1, event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 10 : 1)),
                around: location(of: event))
        }
    }

    override func magnify(with event: NSEvent) {
        model?.zoom(by: 1 + event.magnification, around: location(of: event))
    }
}
