//
//  GraphCanvasModel+Camera.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import QuartzCore
import simd

extension GraphCanvasModel {
    // MARK: - カメラを飛ばす

    /// 点へカメラを飛ばす（遠ければ、いったん引いてから近づく）。
    public func fly(toNode nodeID: Int) {
        guard let index = index(of: nodeID), positions.indices.contains(index) else { return }
        var target = camera
        target.center = displayedPosition(index)
        target.zoom = max(camera.zoom, Self.comfortableZoom)
        fly(to: target)
    }

    /// まとまりの全体が見えるように飛ぶ。
    public func fly(toGroup groupID: Int) {
        let points = members(ofGroup: groupID).map { positions[$0].xyz }
        guard !points.isEmpty else { return }
        fly(to: camera.fitting(points, margin: 0.7))
    }

    /// すべての点が収まるようにする。
    public func fitAll(animated: Bool = true) {
        guard !positions.isEmpty else { return }
        let target = camera.fitting(positions.map(\.xyz))
        if animated {
            fly(to: target)
        } else {
            camera = target
            needsFrame = true
        }
    }

    /// ラベルが読める程度の拡大（点と点の間隔がおよそ 48 pt）。
    static var comfortableZoom: Float { 48 / LayoutParams.spacing }

    func fly(to target: GraphCamera) {
        followsLayout = false
        followsAfterFlight = false
        flight = (CameraFlight(from: camera, to: target), CACurrentMediaTime())
        needsFrame = true
    }

    /// 点が画面の端や外にあれば、見えるところへ動かす。
    func reveal(_ nodeID: Int) {
        guard let index = index(of: nodeID), projected.indices.contains(index) else { return }
        let screen = projected[index].screen
        let limit = camera.viewSize * 0.36
        if abs(screen.x) > limit.x || abs(screen.y) > limit.y || projected[index].look.y < 2 {
            fly(toNode: nodeID)
        }
    }

    // MARK: - フレームごと

    /// カメラを進める。動いているあいだ true。
    func updateCamera(now: Double) -> Bool {
        var moving = false
        if let (flight, start) = flight {
            let progress = (now - start) / flight.duration
            var next = flight.camera(at: progress)
            next.viewSize = camera.viewSize
            camera = next
            if progress >= 1 {
                self.flight = nil
                if followsAfterFlight, !isSettled { followsLayout = true }
                followsAfterFlight = false
            }
            moving = true
        } else if followsLayout, !positions.isEmpty {
            // 落ち着くまでは、全体が収まるようにカメラをなめらかに合わせる
            let target = camera.fitting(positions.map(\.xyz))
            camera.center += (target.center - camera.center) * 0.2
            camera.zoom += (target.zoom - camera.zoom) * 0.2
            if isSettled, abs(target.zoom - camera.zoom) < target.zoom * 0.005 { followsLayout = false }
            moving = true
        }
        if let spinStart, flight == nil {
            // 立体にした直後だけ、ゆっくり回して奥行きを見せる
            let elapsed = now - spinStart
            if elapsed < 3.2 {
                camera.yaw += Float(sin(min(max(elapsed / 3.2, 0), 1) * .pi)) * 0.006
                moving = true
            } else {
                self.spinStart = nil
            }
        }
        return moving
    }

    // MARK: - 操作

    /// 画面を動かす（ずれは pt、上が正）。
    func pan(by delta: CGSize) {
        stopAutomaticCamera()
        camera.center -= camera.worldOffset(forScreen: SIMD2(Float(delta.width), Float(delta.height)))
        needsFrame = true
    }

    /// 3 次元で見ているとき、中心の周りを回る。
    func orbit(by delta: CGSize) {
        stopAutomaticCamera()
        camera.yaw += Float(delta.width) * 0.008
        camera.pitch = min(max(camera.pitch - Float(delta.height) * 0.008, -1.45), 1.45)
        needsFrame = true
    }

    /// トラックパッドの 2 本指の回転。
    func rotate(by degrees: Float) {
        guard is3D else { return }
        stopAutomaticCamera()
        camera.yaw -= degrees * .pi / 180
        needsFrame = true
    }

    /// `point`（View の座標、左下が原点）を中心に拡大・縮小する。
    func zoom(by factor: CGFloat, around point: CGPoint) {
        stopAutomaticCamera()
        let offset = centered(point)
        let anchor = camera.center + camera.worldOffset(forScreen: offset)
        camera.zoom *= Float(factor)
        camera.clampZoom()
        camera.center = anchor - camera.worldOffset(forScreen: offset)
        needsFrame = true
    }

    func stopAutomaticCamera() {
        followsLayout = false
        followsAfterFlight = false
        flight = nil
        spinStart = nil
    }

    // MARK: - 座標

    /// View の座標（左下が原点）を、画面の中央からのずれ（上が正）にする。
    func centered(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(point.x) - camera.viewSize.x / 2, Float(point.y) - camera.viewSize.y / 2)
    }

    /// 画面の中央からのずれを、SwiftUI の座標（左上が原点）にする。
    func swiftUIPoint(_ screen: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(camera.viewSize.x / 2 + screen.x), y: CGFloat(camera.viewSize.y / 2 - screen.y))
    }

    /// 寄せた後の点の座標。
    func displayedPosition(_ index: Int) -> SIMD3<Float> {
        let base = positions[index].xyz
        let lens = states.indices.contains(index) ? states[index].lens : .zero
        return base + (lens.xyz - base) * lens.w
    }
}
