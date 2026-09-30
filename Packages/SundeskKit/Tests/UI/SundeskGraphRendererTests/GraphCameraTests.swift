//
//  GraphCameraTests.swift
//  SundeskGraphRendererTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import Testing
import simd

@testable import SundeskGraphRenderer

@MainActor
@Suite("カメラ")
struct GraphCameraTests {
    private func camera(center: SIMD3<Float> = .zero, zoom: Float = 1) -> GraphCamera {
        var camera = GraphCamera()
        camera.center = center
        camera.zoom = zoom
        camera.viewSize = [800, 600]
        return camera
    }

    @Test("平面では、画面のずれとワールドのずれを行き来できる")
    func flatRoundTrip() {
        let camera = camera(center: [10, -5, 0], zoom: 2)
        let point = SIMD3<Float>(30, 15, 0)

        let projected = camera.project(point)
        let back = camera.center + camera.worldOffset(forScreen: SIMD2(projected.x, projected.y))

        #expect(projected.z == 1)
        #expect(simd_distance(back, point) < 1e-4)
    }

    @Test("トラックパッドの 2 本指では、中身が指と同じ向きに動く（ナチュラルなスクロール）")
    func trackpadPanFollowsFingers() {
        // ナチュラルなスクロールで指を右上へ動かすと、scrollingDeltaX は正、scrollingDeltaY は負になる
        let offset = GraphMTKView.panOffset(scrollingDeltaX: 10, scrollingDeltaY: -6)
        let model = GraphCanvasModel()
        model.camera = camera()
        let point = SIMD3<Float>(20, 30, 0)
        let before = model.camera.project(point)

        model.pan(by: offset)

        let after = model.camera.project(point)
        #expect(abs(after.x - before.x - 10) < 1e-3)
        #expect(abs(after.y - before.y - 6) < 1e-3)
    }

    @Test("透視では、手前の点ほど大きく写る")
    func perspectiveScalesNearPoints() {
        var camera = camera()
        camera.perspective = 1

        let near = camera.project([0, 0, 100])
        let far = camera.project([0, 0, -100])

        #expect(near.z > 1)
        #expect(far.z < 1)
    }

    @Test("遠くへ飛ぶときは、途中でいったん引いて全体を見せる")
    func flightZoomsOutOnLongTrips() {
        let start = camera(center: .zero, zoom: 2)
        let end = camera(center: [5000, 0, 0], zoom: 2)
        let flight = CameraFlight(from: start, to: end)

        let middle = flight.camera(at: 0.5)

        #expect(flight.camera(at: 0) == start)
        #expect(flight.camera(at: 1) == end)
        #expect(middle.zoom < 1)
        #expect(middle.center.x > 0 && middle.center.x < 5000)
        #expect(flight.duration >= 0.45 && flight.duration <= 1.6)
    }

    @Test("近くへは、引かずに移る")
    func flightStaysCloseOnShortTrips() {
        let start = camera(center: .zero, zoom: 2)
        let end = camera(center: [10, 0, 0], zoom: 2)

        let middle = CameraFlight(from: start, to: end).camera(at: 0.5)

        #expect(middle.zoom > 1.9)
    }

    @Test("すべての点が画面に収まるように合わせる")
    func fittingContainsAllPoints() {
        let points: [SIMD3<Float>] = [[-400, -100, 0], [900, 300, 0], [100, 700, 0]]

        let fitted = camera().fitting(points)

        for point in points {
            let projected = fitted.project(point)
            #expect(abs(projected.x) <= 400 && abs(projected.y) <= 300)
        }
    }
}

@MainActor
@Suite("ラベルの置き方")
struct LabelPlacerTests {
    private let entry = LabelAtlas.Entry(uv: [0, 0, 1, 1], size: [60, 20], textSize: [54, 14])

    private func candidate(_ key: Int, at center: SIMD2<Float>, forced: Bool = false) -> LabelPlacer.Candidate {
        LabelPlacer.Candidate(key: key, center: center, entry: entry, scale: 1, color: [1, 1, 1, 1], isForced: forced)
    }

    @Test("重なるラベルは先に置いたほうだけを出し、選んだ点のラベルは重なっても出す")
    func avoidsOverlaps() {
        var placer = LabelPlacer()

        let instances = placer.place(
            [
                candidate(0, at: [0, 0]), candidate(1, at: [10, 0]), candidate(2, at: [0, 100]),
                candidate(3, at: [5, 5], forced: true),
            ],
            budget: 10, viewport: [800, 600], elapsed: 1
        ) { _ in nil }

        #expect(Set(placer.alphas.keys) == [0, 2, 3])
        #expect(instances.count == 3)
    }

    @Test("出す数を超えたら置かず、出し入れはふわっと変える")
    func respectsBudgetAndFades() {
        var placer = LabelPlacer()
        let candidates = [candidate(0, at: [0, 0]), candidate(1, at: [0, 100])]

        _ = placer.place(candidates, budget: 1, viewport: [800, 600], elapsed: 0.05) { _ in nil }
        let first = placer.alphas[0] ?? 0
        _ = placer.place(candidates, budget: 1, viewport: [800, 600], elapsed: 0.05) { _ in nil }

        #expect(placer.alphas[1] == nil)
        #expect(first > 0 && first < 1)
        #expect((placer.alphas[0] ?? 0) > first)
    }

    @Test("升目で覚えた四角の重なりを見分ける")
    func occupancyGrid() {
        var grid = OccupancyGrid()
        grid.insert([0, 0, 50, 20])

        #expect(grid.intersects([40, 10, 90, 30]))
        #expect(!grid.intersects([60, 0, 100, 20]))
        #expect(!grid.intersects([-200, -200, -150, -180]))
    }
}
