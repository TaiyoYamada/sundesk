//
//  GraphMTKView.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import MetalKit

/// マウス、トラックパッド、キーボードの操作を受ける MTKView。
final class GraphMTKView: MTKView {
    weak var model: GraphCanvasModel?
    private var draggingNode: Int?
    private var dragStart: CGPoint?
    private var lastDragPoint: CGPoint?
    private var didDrag = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        model?.viewSize = newSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor { layer?.contentsScale = scale }
        updateAppearance()
    }

    func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        model?.setAppearance(isDark: isDark, pixelScale: Float(window?.backingScaleFactor ?? 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    // MARK: - マウス

    override func mouseMoved(with event: NSEvent) {
        model?.hover(at: location(of: event))
        (model?.isHoveringNode == true ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        model?.hover(at: nil)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = location(of: event)
        if event.clickCount == 2 {
            model?.doubleClick(at: point)
            dragStart = nil
            return
        }
        dragStart = point
        lastDragPoint = point
        didDrag = false
        draggingNode = model?.hitTest(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let start = dragStart else { return }
        let point = location(of: event)
        if hypot(point.x - start.x, point.y - start.y) > 3 { didDrag = true }
        guard didDrag else { return }
        let last = lastDragPoint ?? point
        lastDragPoint = point
        let delta = CGSize(width: point.x - last.x, height: point.y - last.y)
        if let draggingNode {
            model.drag(node: draggingNode, to: point)
        } else if model.is3D, !event.modifierFlags.contains(.option) {
            model.orbit(by: delta)
        } else {
            model.pan(by: delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model, dragStart != nil else { return }
        if let draggingNode {
            model.release(node: draggingNode)
        }
        if !didDrag {
            model.click(at: location(of: event), extending: event.modifierFlags.contains(.shift))
        }
        draggingNode = nil
        dragStart = nil
    }

    override func rightMouseDragged(with event: NSEvent) {
        model?.pan(by: CGSize(width: event.deltaX, height: -event.deltaY))
    }

    // MARK: - トラックパッド

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

    override func rotate(with event: NSEvent) {
        model?.rotate(by: event.rotation)
    }

    // MARK: - キーボード

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: model.moveSelection(toward: [-1, 0])
        case 124: model.moveSelection(toward: [1, 0])
        case 125: model.moveSelection(toward: [0, -1])
        case 126: model.moveSelection(toward: [0, 1])
        case 53: model.escape()
        case 36, 76: model.openSelection()
        default: super.keyDown(with: event)
        }
    }
}
