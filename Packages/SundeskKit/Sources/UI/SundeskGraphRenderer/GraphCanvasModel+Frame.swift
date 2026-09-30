//
//  GraphCanvasModel+Frame.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import MetalKit
import QuartzCore
import simd

extension GraphCanvasModel {
    /// 1 フレーム分の計算をして、描くものを返す。何も変わっていなければ nil（描かずに休む）。
    func makeFrame(view: MTKView?) -> GraphFrame? {
        guard let renderer else { return nil }
        let now = CACurrentMediaTime()
        let elapsed = Float(min(max(now - lastFrameTime, 1.0 / 240), 0.1))
        lastFrameTime = now
        positions = renderer.layout.readPositions()

        var animating = !isSettled
        animating = updateCamera(now: now) || animating
        animating = updateTimeline(elapsed: elapsed) || animating
        if emphasisNeedsUpdate { updateEmphasis() }
        animating = updateNodeStates(elapsed: elapsed, now: now) || animating
        guard animating || needsFrame || !pathNodeIDs.isEmpty || !labelsAreSettled else { return nil }
        needsFrame = false

        renderer.states.write(states)
        projectAll()
        updateCentroids()
        updateOrder()
        updateLabels(elapsed: elapsed)
        updateAnchors()
        return GraphFrame(
            uniforms: uniforms(now: now), layoutSteps: isSettled ? 0 : 2, drawsClouds: cloudAlpha > 0.01,
            edgeCount: Int(edgeBudget.rounded(.up)))
    }

    // MARK: - 見た目の段階（拡大の度合いで変える）

    /// 点と点の間隔（画面の pt）。遠くから眺めているほど小さい。
    var screenSpacing: Float { LayoutParams.spacing * camera.zoom }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        GraphProjection.smoothstep(edge0, edge1, value)
    }

    /// 雲の濃さ。遠くから眺めているときに濃く、近づくと消える。
    var cloudAlpha: Float {
        guard namedGroups.count >= 2 else { return 0 }
        return (1 - Self.smoothstep(26, 64, screenSpacing)) * (1 - 0.65 * focusAmount) * (1 - 0.5 * camera.perspective)
    }

    /// まとまりの名前の濃さ。
    var groupLabelAlpha: Float {
        guard namedGroups.count >= 2 else { return 0 }
        return (1 - Self.smoothstep(24, 42, screenSpacing)) * (1 - 0.8 * focusAmount)
    }

    /// 描く線の数（重い順）。遠くからは重い線だけにする。
    var edgeBudget: Float {
        let count = Float(renderer?.edges.count ?? 0)
        let fraction = 0.2 + 0.8 * Self.smoothstep(10, 36, screenSpacing)
        return max(min(count, 1500), count * fraction)
    }

    /// 点の大きさの倍率。拡大すると少し大きく、縮小すると少し小さくする。
    var nodeScale: Float { pow(min(max(camera.zoom, 0.2), 2.4), 0.8) * 0.9 }

    private func uniforms(now: Double) -> GraphUniforms {
        let (inner, outer) = GraphPalette.background(isDark: isDark)
        let edgeAlpha: Float = isDark ? 0.55 : 0.5
        let density = min(max(2500 / max(edgeBudget, 1), 0.45), 1)
        return GraphUniforms(
            view: camera.viewMatrix, center: SIMD4(camera.center, 0),
            viewport: SIMD4(camera.viewSize.x, camera.viewSize.y, pixelScale, camera.zoom),
            camera: SIMD4(
                camera.perspective, camera.eyeDistance, Float((now - clockStart).truncatingRemainder(dividingBy: 3600)),
                timelineCursor.map(Float.init) ?? GraphUniforms.timelineOff),
            style: SIMD4(isDark ? 1 : 0, cloudAlpha, edgeAlpha * density * (1 - 0.8 * focusAmount), nodeScale),
            extra: SIMD4(edgeBudget, 0.55, LayoutParams.spacing * 2.4, 0),
            background0: inner, background1: outer)
    }

    // MARK: - CPU で画面に写す（ラベルと、押した点を探すのに使う）

    func projectAll() {
        let context = GraphProjection.Context(
            camera: camera, nodeScale: nodeScale, cursor: timelineCursor.map(Float.init) ?? GraphUniforms.timelineOff)
        projected = positions.indices.map { index in
            GraphProjection.project(
                position: positions[index], info: info[index], state: states[index], context: context)
        }
    }

    /// 描く順。3 次元では奥から手前へ、強調する点は最後に描く（上に重なる）。
    private func updateOrder() {
        let indices = Array(projected.indices)
        let sorted: [Int]
        let isFlat = camera.perspective <= 0.01
        // 平面では、強調が変わったときだけ並べ直す
        if isFlat, orderIsFlat, !emphasisChangedSinceOrder { return }
        orderIsFlat = isFlat
        emphasisChangedSinceOrder = false
        if !isFlat {
            sorted = indices.sorted {
                let first = (projected[$0].world.w > 0 ? 1 : 0, projected[$0].screen.w)
                let second = (projected[$1].world.w > 0 ? 1 : 0, projected[$1].screen.w)
                return first < second
            }
        } else {
            sorted = indices.filter { projected[$0].world.w == 0 } + indices.filter { projected[$0].world.w > 0 }
        }
        renderer?.order.write(sorted.map { UInt32($0) })
    }

    /// SwiftUI に知らせる値（選んだ点の画面の位置、ノートを出す濃さ）。変わったときだけ書き換える。
    private func updateAnchors() {
        var anchor: CGPoint?
        var radius: Double = 0
        if let index = index(of: selectedNodeID), projected.indices.contains(index) {
            let screen = SIMD2(projected[index].screen.x, projected[index].screen.y)
            let half = camera.viewSize / 2
            if abs(screen.x) < half.x, abs(screen.y) < half.y {
                anchor = swiftUIPoint(screen)
                radius = Double(projected[index].look.y)
            }
        }
        let detail = anchor == nil ? 0 : Double(Self.smoothstep(64, 96, screenSpacing))
        if abs(detail - noteDetail) > 0.01 || (detail == 0) != (noteDetail == 0) { noteDetail = detail }
        let moved =
            switch (anchor, selectionAnchor) {
            case (nil, nil): false
            case (let new?, let old?): hypot(new.x - old.x, new.y - old.y) > 0.5
            default: true
            }
        if moved { selectionAnchor = anchor }
        if abs(radius - selectionRadius) > 0.5 { selectionRadius = radius }
    }
}
