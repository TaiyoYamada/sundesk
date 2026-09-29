//
//  GraphLayoutTests.swift
//  SundeskGraphRendererTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Metal
import Testing

@testable import SundeskGraphRenderer

@MainActor
@Suite("知識グラフの描画")
struct GraphLayoutTests {
    private let scene = GraphScene(
        nodes: (0..<40).map {
            GraphScene.Node(id: $0 * 10, label: "概念\($0)", radius: Float(4 + $0 % 5), group: $0 % 4)
        },
        edges: (0..<39).map { GraphScene.Edge(source: $0, target: ($0 * 7 + 3) % 40, weight: 1) }
    )

    @Test("GPU のレイアウト計算が、CPU の参照実装と一致する")
    func gpuMatchesReference() throws {
        let renderer = try #require(GraphRenderer())
        let initial = scene.initialPositions(spacing: LayoutParams.spacing)
        renderer.load(scene, positions: initial)

        var expected = initial
        var velocities = [SIMD2<Float>](repeating: .zero, count: initial.count)
        var alpha: Float = 1
        for _ in 0..<5 {
            expected = GraphLayoutReference.step(
                positions: expected, velocities: &velocities, scene: scene,
                params: .standard(nodeCount: scene.nodes.count, alpha: alpha))
            alpha *= GraphLayoutEngine.alphaDecay
        }
        renderer.layout.run(steps: 5)
        let actual = renderer.layout.readPositions()

        #expect(actual.count == expected.count)
        for (lhs, rhs) in zip(actual, expected) {
            #expect(abs(lhs.x - rhs.x) < 0.05 && abs(lhs.y - rhs.y) < 0.05, "\(lhs) と \(rhs)")
        }
    }

    @Test("温度が下がりきると止まる")
    func settles() throws {
        let renderer = try #require(GraphRenderer())
        renderer.load(scene, positions: scene.initialPositions(spacing: LayoutParams.spacing))

        renderer.layout.run(steps: 400)

        #expect(renderer.layout.isSettled)
        #expect(renderer.layout.readPositions().allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test("つながった点は、つながっていない点より近くに落ち着く")
    func connectedNodesAreCloser() throws {
        let scene = GraphScene(
            nodes: (0..<6).map { GraphScene.Node(id: $0, label: "\($0)", radius: 5, group: 0) },
            edges: [.init(source: 0, target: 1, weight: 2), .init(source: 2, target: 3, weight: 2)]
        )
        let renderer = try #require(GraphRenderer())
        renderer.load(scene, positions: scene.initialPositions(spacing: LayoutParams.spacing))
        renderer.layout.run(steps: 400)
        let positions = renderer.layout.readPositions()

        func distance(_ first: Int, _ second: Int) -> Float {
            let delta = positions[first] - positions[second]
            return (delta * delta).sum().squareRoot()
        }
        #expect(distance(0, 1) < distance(0, 4))
        #expect(distance(2, 3) < distance(2, 5))
    }

    @Test("画面の座標とグラフの座標を行き来でき、押した点を選べる")
    func hitTestingAndSelection() throws {
        let model = GraphCanvasModel()
        try #require(model.isAvailable)
        model.viewSize = CGSize(width: 400, height: 300)
        model.setScene(scene)
        var selected: [Int?] = []
        model.onSelect = { selected.append($0) }

        let position = model.positions()[3]
        let flipped = model.screen(position)
        model.click(at: CGPoint(x: flipped.x, y: model.viewSize.height - flipped.y))
        model.click(at: CGPoint(x: -1000, y: -1000))

        #expect(selected == [30, nil])
        #expect(model.selectedNodeID == nil)
    }

    @Test("ラベルは大きい点と、選んだ点の隣に出す")
    func labels() throws {
        let model = GraphCanvasModel()
        try #require(model.isAvailable)
        model.viewSize = CGSize(width: 2000, height: 2000)
        model.setScene(scene)
        model.fitAll()

        model.select(nodeID: 0)

        let labels = model.labels(limit: 3)
        #expect(labels.contains { $0.id == 0 && $0.isEmphasized })
        #expect(labels.contains { $0.id == 30 && $0.isEmphasized })  // 0 番と 3 番はつながっている
        #expect(labels.filter { !$0.isEmphasized }.count <= 3)
    }
}
