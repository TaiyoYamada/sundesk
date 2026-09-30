//
//  GraphLayoutTests.swift
//  SundeskGraphRendererTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Metal
import Testing
import simd

@testable import SundeskGraphRenderer

/// GPU を使うテスト（CI では別の手順で動かすので、GPU を使うものはこの型の中にまとめる）。
@MainActor
@Suite("知識グラフの描画")
struct GraphLayoutTests {
    static let scene = GraphScene(
        nodes: (0..<40).map {
            GraphScene.Node(id: $0 * 10, label: "概念\($0)", radius: Float(4 + $0 % 5), group: $0 % 4)
        },
        edges: (0..<39).map { GraphScene.Edge(source: $0, target: ($0 * 7 + 3) % 40, weight: 1) }
    )

    private var scene: GraphScene { Self.scene }

    @Test("GPU のレイアウト計算が、CPU の参照実装と一致する（まとまりの中心へ引く力を含む）")
    func gpuMatchesReference() throws {
        let renderer = try #require(GraphRenderer())
        let initial = scene.initialPositions(spacing: LayoutParams.spacing)
        let groups = scene.nodes.map { UInt32($0.group) }
        renderer.layout.load(scene, positions: initial, groups: groups)

        var expected = initial
        var velocities = [SIMD4<Float>](repeating: .zero, count: initial.count)
        var alpha: Float = 1
        for _ in 0..<5 {
            expected = GraphLayoutReference.step(
                positions: expected, velocities: &velocities, scene: scene,
                params: .standard(nodeCount: scene.nodes.count, alpha: alpha), groups: groups)
            alpha *= GraphLayoutEngine.alphaDecay
        }
        renderer.layout.run(steps: 5)
        let actual = renderer.layout.readPositions()

        #expect(actual.count == expected.count)
        for (lhs, rhs) in zip(actual, expected) {
            #expect(simd_distance(lhs.xyz, rhs.xyz) < 0.05, "\(lhs) と \(rhs)")
        }
    }

    @Test("奥行きをつけた配置と、平面に戻す計算も、CPU の参照実装と一致する")
    func depthMatchesReference() throws {
        let renderer = try #require(GraphRenderer())
        var initial = scene.initialPositions(spacing: LayoutParams.spacing)
        for index in initial.indices { initial[index].z = Float(index % 7 - 3) * 20 }
        renderer.layout.load(scene, positions: initial)
        renderer.layout.setDepth(false)

        var expected = initial
        var velocities = [SIMD4<Float>](repeating: .zero, count: initial.count)
        var alpha: Float = 1
        for _ in 0..<4 {
            expected = GraphLayoutReference.step(
                positions: expected, velocities: &velocities, scene: scene,
                params: .standard(
                    nodeCount: scene.nodes.count, alpha: alpha, flatten: GraphLayoutEngine.flattenRate))
            alpha *= GraphLayoutEngine.alphaDecay
        }
        renderer.layout.run(steps: 4)
        let actual = renderer.layout.readPositions()

        for (lhs, rhs) in zip(actual, expected) {
            #expect(simd_distance(lhs.xyz, rhs.xyz) < 0.05, "\(lhs) と \(rhs)")
        }
        #expect(actual.map { abs($0.z) }.max()! < initial.map { abs($0.z) }.max()!)
    }

    @Test("温度が下がりきると止まり、平面なら奥行きは 0 のまま")
    func settles() throws {
        let renderer = try #require(GraphRenderer())
        renderer.layout.load(scene, positions: scene.initialPositions(spacing: LayoutParams.spacing))

        renderer.layout.run(steps: 400)

        #expect(renderer.layout.isSettled)
        let positions = renderer.layout.readPositions()
        #expect(positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z == 0 })
    }

    @Test("奥行きをつけると立体にほどけ、平面に戻すとつぶれる")
    func depthUnfoldsAndFlattens() throws {
        let renderer = try #require(GraphRenderer())
        renderer.layout.load(scene, positions: scene.initialPositions(spacing: LayoutParams.spacing))
        renderer.layout.run(steps: 200)

        renderer.layout.setDepth(true)
        renderer.layout.run(steps: 200)
        let unfolded = renderer.layout.readPositions().map { abs($0.z) }.max() ?? 0
        renderer.layout.setDepth(false)
        renderer.layout.run(steps: 300)
        let flattened = renderer.layout.readPositions().map { abs($0.z) }.max() ?? 0

        #expect(unfolded > LayoutParams.spacing)
        #expect(flattened < 0.5)
    }

    @Test("つながった点は、つながっていない点より近くに落ち着く")
    func connectedNodesAreCloser() throws {
        let scene = GraphScene(
            nodes: (0..<6).map { GraphScene.Node(id: $0, label: "\($0)", radius: 5, group: 0) },
            edges: [.init(source: 0, target: 1, weight: 2), .init(source: 2, target: 3, weight: 2)]
        )
        let renderer = try #require(GraphRenderer())
        renderer.layout.load(scene, positions: scene.initialPositions(spacing: LayoutParams.spacing))
        renderer.layout.run(steps: 400)
        let positions = renderer.layout.readPositions()

        func distance(_ first: Int, _ second: Int) -> Float {
            simd_distance(positions[first].xyz, positions[second].xyz)
        }
        #expect(distance(0, 1) < distance(0, 4))
        #expect(distance(2, 3) < distance(2, 5))
    }

    /// 実際の知識グラフに近い形（よくつながった固まりと、どこにもつながらない点）。
    @Test("よくつながった固まりはつぶれず、どこにもつながらない点も遠くへ飛ばない")
    func denseGraphStaysReadable() throws {
        var generator = SeededGenerator(seed: 42)
        let (core, isolated) = (250, 40)
        let nodes = (0..<(core + isolated)).map { GraphScene.Node(id: $0, label: "\($0)", radius: 5, group: 0) }
        let edges = (0..<2000).map { _ in
            GraphScene.Edge(
                source: Int.random(in: 0..<core, using: &generator),
                target: Int.random(in: 0..<core, using: &generator),
                weight: Float.random(in: 0.5...2, using: &generator))
        }
        let scene = GraphScene(nodes: nodes, edges: edges)
        let renderer = try #require(GraphRenderer())
        renderer.layout.load(scene, positions: scene.initialPositions(spacing: LayoutParams.spacing))
        renderer.layout.run(steps: 400)
        let positions = renderer.layout.readPositions().map(\.xyz)

        let radii = positions.map { simd_length($0) }
        let coreRadius = radii[0..<core].sorted()[core * 9 / 10]
        let outer = try #require(radii[core...].max())
        #expect(outer < coreRadius * 4, "つながらない点が \(outer) まで飛んだ（固まりは \(coreRadius)）")
        let nearest = (0..<core).map { index in
            (0..<core).filter { $0 != index }.map { simd_distance(positions[index], positions[$0]) }.min() ?? 0
        }
        #expect(nearest.sorted()[core / 2] > LayoutParams.spacing * 0.4, "固まりがつぶれている")
    }

    @Test("まとまりの中心へ引くと、同じまとまりの点どうしが、引かないときより近くに集まる")
    func groupsStayTogether() throws {
        var generator = SeededGenerator(seed: 3)
        let nodes = (0..<120).map { GraphScene.Node(id: $0, label: "\($0)", radius: 5, group: $0 % 3) }
        let edges = (0..<400).map { index in
            let source = Int.random(in: 0..<120, using: &generator)
            var target = Int.random(in: 0..<120, using: &generator)
            if index % 5 != 0 { target = target / 3 * 3 + source % 3 }  // 8 割は同じまとまりの中
            return GraphScene.Edge(source: source, target: min(target, 119), weight: 1)
        }
        let scene = GraphScene(nodes: nodes, edges: edges)

        func separation(groups: [UInt32]?) throws -> Float {
            let renderer = try #require(GraphRenderer())
            renderer.layout.load(
                scene, positions: scene.initialPositions(spacing: LayoutParams.spacing), groups: groups)
            renderer.layout.run(steps: 400)
            let positions = renderer.layout.readPositions().map(\.xyz)
            var same: [Float] = []
            var other: [Float] = []
            for first in 0..<120 {
                for second in (first + 1)..<120 {
                    let distance = simd_distance(positions[first], positions[second])
                    if nodes[first].group == nodes[second].group {
                        same.append(distance)
                    } else {
                        other.append(distance)
                    }
                }
            }
            return same.reduce(0, +) / Float(same.count) / (other.reduce(0, +) / Float(other.count))
        }

        #expect(try separation(groups: nodes.map { UInt32($0.group) }) < separation(groups: nil))
    }
}
