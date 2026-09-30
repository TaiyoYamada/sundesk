//
//  GraphCanvasModelTests.swift
//  SundeskGraphRendererTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import Metal
import Testing
import simd

@testable import SundeskGraphRenderer

extension GraphLayoutTests {
    @MainActor
    @Suite("画面に写す")
    struct Projection {
        @Test("GPU で画面に写した結果が、CPU の参照実装と一致する（寄せ方、奥行き、時間の再生を含む）")
        func gpuMatchesReference() throws {
            let scene = GraphLayoutTests.scene
            let renderer = try #require(GraphRenderer())
            var positions = scene.initialPositions(spacing: LayoutParams.spacing)
            for index in positions.indices { positions[index].z = Float(index % 5) * 15 - 30 }
            let info = scene.nodes.enumerated().map { index, node in
                NodeInfo(node.radius, index % 3 == 0 ? -1 : Float(index) / 40, Float(node.group), 1)
            }
            renderer.load(
                scene, positions: positions, info: info, groups: scene.nodes.map { _ in GraphLayoutEngine.noGroup })
            let states = scene.nodes.indices.map { index in
                NodeState(
                    lens: SIMD4(Float(index), -Float(index), 5, Float(index % 4) / 3),
                    anim: SIMD4(index % 2 == 0 ? 1 : 0.2, Float(index % 3), Float(index % 5) / 4, -1))
            }
            renderer.states.write(states)
            var camera = GraphCamera()
            camera.center = [12, -8, 3]
            camera.zoom = 1.7
            camera.yaw = 0.6
            camera.pitch = -0.3
            camera.perspective = 0.8
            camera.viewSize = [900, 700]
            let cursor: Float = 0.45
            let uniforms = GraphUniforms(
                view: camera.viewMatrix, center: SIMD4(camera.center, 0),
                viewport: SIMD4(camera.viewSize.x, camera.viewSize.y, 2, camera.zoom),
                camera: SIMD4(camera.perspective, camera.eyeDistance, 0, cursor), style: SIMD4(1, 0, 0, 1.3),
                extra: .zero, background0: .zero, background1: .zero)

            let actual = renderer.runProjection(uniforms: uniforms)

            let context = GraphProjection.Context(camera: camera, nodeScale: 1.3, cursor: cursor)
            #expect(actual.count == scene.nodes.count)
            for index in actual.indices {
                let expected = GraphProjection.project(
                    position: positions[index], info: info[index], state: states[index], context: context)
                let node = actual[index]
                #expect(simd_distance(node.screen, expected.screen) < 0.01 * max(1, simd_length(expected.screen)))
                #expect(simd_distance(node.look, expected.look) < 0.002 * max(1, simd_length(expected.look)))
                #expect(simd_distance(node.world, expected.world) < 0.001 * max(1, simd_length(expected.world)))
            }
        }
    }

    @MainActor
    @Suite("キャンバスの操作")
    struct Canvas {
        private func makeModel() throws -> GraphCanvasModel {
            let model = GraphCanvasModel()
            try #require(model.isAvailable)
            model.viewSize = CGSize(width: 900, height: 700)
            let scene = GraphLayoutTests.scene
            model.setScene(
                GraphScene(
                    nodes: scene.nodes, edges: scene.edges,
                    groups: (0..<4).map { GraphScene.Group(id: $0, name: "分野\($0)") }))
            model.renderer?.layout.run(steps: 300)
            model.fitAll(animated: false)
            _ = model.makeFrame()
            return model
        }

        /// 点の中心（View の座標、左下が原点）。
        private func point(of index: Int, in model: GraphCanvasModel) -> CGPoint {
            let screen = model.projected[index].screen
            return CGPoint(
                x: CGFloat(screen.x + model.camera.viewSize.x / 2), y: CGFloat(screen.y + model.camera.viewSize.y / 2))
        }

        @Test("押した点を選び、空いているところを押すと選択を外す")
        func clickSelects() throws {
            let model = try makeModel()
            var selected: [Int?] = []
            model.onSelect = { selected.append($0) }

            model.click(at: point(of: 3, in: model), extending: false)
            model.click(at: CGPoint(x: -1000, y: -1000), extending: false)

            #expect(selected == [30, nil])
            #expect(model.selectedNodeID == nil)
        }

        @Test("⇧ を押しながら別の点を押すと、選んだ点からの経路をたずね、Esc で経路、選択の順に消す")
        func shiftClickAsksForPath() throws {
            let model = try makeModel()
            var targets: [Int?] = []
            var selected: [Int?] = []
            model.onPathTarget = { targets.append($0) }
            model.onSelect = { selected.append($0) }
            model.select(nodeID: 0)

            model.click(at: point(of: 5, in: model), extending: true)
            model.setPath([0, 30, 50])
            model.escape()
            model.setPath([])
            model.escape()

            #expect(targets == [50, nil])
            #expect(selected == [nil])
            #expect(model.selectedNodeID == nil)
        }

        @Test("選ぶと、隣の点が選んだ点のまわりへ寄り、ほかは薄くなる")
        func focusPullsNeighbors() throws {
            let model = try makeModel()
            let selected = 0
            let neighbor = try #require(model.neighborIndices[selected].first)
            let other = try #require(
                model.scene.nodes.indices.first { $0 != selected && !model.neighborIndices[selected].contains($0) })
            let before = simd_distance(model.displayedPosition(neighbor), model.positions[selected].xyz)

            model.select(nodeID: model.scene.nodes[selected].id)
            for _ in 0..<90 {
                model.lastFrameTime -= 1.0 / 60
                _ = model.makeFrame()
            }

            let ring = 92 / min(model.camera.zoom, model.lensZoom ?? model.camera.zoom)
            let after = simd_distance(model.displayedPosition(neighbor), model.positions[selected].xyz)
            #expect(abs(after - ring) < ring * 0.05, "寄せる前 \(before)、後 \(after)、円 \(ring)")
            #expect(model.states[neighbor].anim.x > 0.95)
            #expect(model.states[other].anim.x < 0.3)
            #expect(model.states[selected].anim.y == 2)
        }

        @Test("矢印の向きにある隣へ移る")
        func arrowMovesToNeighbor() throws {
            let model = try makeModel()
            var selected: [Int?] = []
            model.onSelect = { selected.append($0) }
            model.select(nodeID: 0)
            let origin = model.projected[0].screen
            let neighbor = try #require(model.neighborIndices[0].first)
            let offset = model.projected[neighbor].screen - origin
            let direction = simd_normalize(SIMD2(offset.x, offset.y))

            model.moveSelection(toward: direction)

            let chosen = try #require(selected.compactMap(\.self).last)
            let index = try #require(model.index(of: chosen))
            let chosenOffset = model.projected[index].screen - origin
            #expect(simd_dot(simd_normalize(SIMD2(chosenOffset.x, chosenOffset.y)), direction) > 0.3)
        }

        @Test("時間を再生すると、その時までに生まれた点だけが見える")
        func timelineShowsBornNodes() throws {
            let scene = GraphScene(
                nodes: (0..<10).map {
                    GraphScene.Node(id: $0, label: "\($0)", radius: 5, group: 0, birth: Float($0) / 9)
                },
                edges: [.init(source: 0, target: 9, weight: 1)])
            let model = GraphCanvasModel()
            try #require(model.isAvailable)
            model.viewSize = CGSize(width: 800, height: 600)
            model.setScene(scene)

            model.setTimelineCursor(0.5)
            _ = model.makeFrame()

            #expect(model.hasTimeline)
            #expect(model.visibleNodeCount == 5)
            #expect(model.projected[0].look.w == 1)
            #expect(model.projected[9].look.w == 0)
            model.closeTimeline()
            #expect(model.visibleNodeCount == 10)
        }

        @Test("遠くからはまとまりの名前、近づくと概念の名前を多く出す")
        func semanticZoom() throws {
            let model = try makeModel()
            model.camera.zoom = 0.3
            let far = (model.groupLabelAlpha, model.labelBudget, model.cloudAlpha)
            model.camera.zoom = 3
            let near = (model.groupLabelAlpha, model.labelBudget, model.cloudAlpha)

            #expect(far.0 > 0.9 && near.0 == 0)
            #expect(far.1 < near.1)
            #expect(far.2 > 0.5 && near.2 == 0)
        }
    }
}
