//
//  GraphCamera.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import simd

/// グラフを見るカメラ。平面では平行投影、3 次元では中心の周りを回る透視投影にする。
struct GraphCamera: Equatable {
    /// 画面の中央に来る座標。
    var center = SIMD3<Float>.zero
    /// 1 単位あたりのポイント。
    var zoom: Float = 1
    /// 縦軸の周りの回転（ラジアン）。
    var yaw: Float = 0
    /// 横軸の周りの回転（ラジアン）。
    var pitch: Float = 0
    /// 奥行きの混ざり具合（0 = 平面、1 = 透視）。切り替えるときに間をなめらかにつなぐ。
    var perspective: Float = 0
    /// 画面の大きさ（ポイント）。
    var viewSize = SIMD2<Float>(800, 600)

    static let zoomRange: ClosedRange<Float> = 0.02...24

    /// 回転（ワールド → 視点）。
    var rotation: simd_float3x3 {
        let yawMatrix = simd_float3x3(
            SIMD3(cos(yaw), 0, -sin(yaw)), SIMD3(0, 1, 0), SIMD3(sin(yaw), 0, cos(yaw)))
        let pitchMatrix = simd_float3x3(
            SIMD3(1, 0, 0), SIMD3(0, cos(pitch), sin(pitch)), SIMD3(0, -sin(pitch), cos(pitch)))
        return pitchMatrix * yawMatrix
    }

    /// 目までの距離（ワールドの単位）。拡大すると目が近づく（画角はおよそ 45 度）。
    var eyeDistance: Float { max(viewSize.x, viewSize.y) / zoom * 1.2 }

    /// 画面に写す。xy = 画面の中央からの位置（pt、上が正）、z = 遠近の倍率、w = 奥行き（手前が正）。
    ///
    /// シェーダーの `projectPoint` と同じ計算。
    func project(_ point: SIMD3<Float>) -> SIMD4<Float> {
        project(point, rotation: rotation)
    }

    func project(_ point: SIMD3<Float>, rotation: simd_float3x3) -> SIMD4<Float> {
        let view = rotation * (point - center)
        let eye = eyeDistance
        let scale = 1 + (eye / max(eye - view.z, eye * 0.05) - 1) * perspective
        let screen = SIMD2(view.x, view.y) * (zoom * scale)
        return SIMD4(screen.x, screen.y, scale, view.z)
    }

    /// 画面の中央からのずれ（pt、上が正）を、中心を通る面の上のワールドのずれにする。
    func worldOffset(forScreen offset: SIMD2<Float>) -> SIMD3<Float> {
        rotation.transpose * SIMD3(offset.x / zoom, offset.y / zoom, 0)
    }

    /// 1 画面に見える幅（ワールドの単位）。
    var visibleWidth: Float { min(viewSize.x, viewSize.y) / zoom }

    mutating func clampZoom() {
        zoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// 点がすべて収まるカメラ（今の向きのまま）。
    func fitting(_ points: [SIMD3<Float>], margin: Float = 0.82) -> GraphCamera {
        guard let first = points.first, viewSize.x > 0, viewSize.y > 0 else { return self }
        let rotation = self.rotation
        var lower = rotation * first
        var upper = lower
        for point in points {
            let view = rotation * point
            lower = simd_min(lower, view)
            upper = simd_max(upper, view)
        }
        var camera = self
        let middle = (lower + upper) / 2
        camera.center = rotation.transpose * SIMD3(middle.x, middle.y, middle.z)
        let extent = simd_max(SIMD2(upper.x - lower.x, upper.y - lower.y), [1, 1])
        let depthMargin = 1 - 0.25 * perspective
        camera.zoom = min(viewSize.x / extent.x, viewSize.y / extent.y) * margin * depthMargin
        camera.clampZoom()
        return camera
    }

    /// シェーダーに渡す回転。
    var viewMatrix: simd_float4x4 {
        let rotation = self.rotation
        return simd_float4x4(
            SIMD4(rotation.columns.0, 0), SIMD4(rotation.columns.1, 0), SIMD4(rotation.columns.2, 0), SIMD4(0, 0, 0, 1))
    }
}

/// 遠くへ飛ぶときの動き（van Wijk と Nuij の「なめらかなズームと移動」）。
///
/// 遠い点へは、いったん引いて全体を見せてから近づく。近い点へは、ほぼまっすぐ移る。
struct CameraFlight {
    let start: GraphCamera
    let end: GraphCamera
    let duration: Double
    private let rho: Float = 1.42
    private let distance: Float
    private let startWidth: Float
    private let endWidth: Float
    private let startLog: Float
    private let length: Float

    /// - Parameter duration: 秒。nil なら、動く量から決める。
    init(from start: GraphCamera, to end: GraphCamera, duration: Double? = nil) {
        self.start = start
        self.end = end
        distance = simd_distance(start.center, end.center)
        startWidth = start.visibleWidth
        endWidth = end.visibleWidth
        let rho2 = rho * rho
        if distance < 1e-3 {
            startLog = 0
            length = abs(log(endWidth / startWidth)) / rho
        } else {
            let startTerm =
                (endWidth * endWidth - startWidth * startWidth + rho2 * rho2 * distance * distance)
                / (2 * startWidth * rho2 * distance)
            let endTerm =
                (endWidth * endWidth - startWidth * startWidth - rho2 * rho2 * distance * distance)
                / (2 * endWidth * rho2 * distance)
            startLog = log(-startTerm + (startTerm * startTerm + 1).squareRoot())
            let endLog = log(-endTerm + (endTerm * endTerm + 1).squareRoot())
            length = (endLog - startLog) / rho
        }
        self.duration = duration ?? Double(min(max(length * 0.32, 0.45), 1.6))
    }

    /// 経過した割合（0〜1）でのカメラ。
    func camera(at progress: Double) -> GraphCamera {
        let eased = Float(Self.ease(min(max(progress, 0), 1)))
        let arc = eased * length
        var camera = end
        let width: Float
        let travelled: Float
        if distance < 1e-3 {
            travelled = 0
            width = startWidth * pow(endWidth / startWidth, eased)
        } else {
            let rho2 = rho * rho
            travelled =
                startWidth / rho2 * cosh(startLog) * tanh(rho * arc + startLog) - startWidth / rho2 * sinh(startLog)
            width = startWidth * cosh(startLog) / cosh(rho * arc + startLog)
        }
        let fraction = distance < 1e-3 ? eased : min(max(travelled / distance, 0), 1)
        camera.center = start.center + (end.center - start.center) * fraction
        camera.zoom = min(camera.viewSize.x, camera.viewSize.y) / max(width, 1e-3)
        camera.yaw = start.yaw + (end.yaw - start.yaw) * eased
        camera.pitch = start.pitch + (end.pitch - start.pitch) * eased
        camera.perspective = start.perspective + (end.perspective - start.perspective) * eased
        camera.clampZoom()
        if progress >= 1 { camera = end }
        return camera
    }

    /// 動き始めと終わりをゆるやかにする。
    static func ease(_ value: Double) -> Double {
        value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }
}
