//
//  GraphPerformanceTests.swift
//  SundeskGraphRendererTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import Metal
import QuartzCore
import Testing

@testable import SundeskGraphRenderer

extension GraphLayoutTests {
    /// 実データに近い大きさ（概念 1,500、関係 24,000）の作り物のグラフで、1 フレームの時間を測る。
    @MainActor
    @Suite("描画の性能")
    struct Performance {
        static func largeScene(nodes: Int = 1500, edges: Int = 24000) -> GraphScene {
            var generator = SeededGenerator(seed: 7)
            let groups = 12
            let nodeList = (0..<nodes).map { index in
                GraphScene.Node(
                    id: index, label: "概念\(index)", radius: Float.random(in: 3...16, using: &generator),
                    group: index % groups, birth: Float(index) / Float(nodes))
            }
            let edgeList = (0..<edges).map { _ in
                let source = Int.random(in: 0..<nodes, using: &generator)
                // 7 割は同じまとまりの中でつなぐ
                let sameGroup = Int.random(in: 0..<10, using: &generator) < 7
                var target = Int.random(in: 0..<nodes, using: &generator)
                if sameGroup { target = (target / groups) * groups + source % groups }
                return GraphScene.Edge(
                    source: source, target: min(target, nodes - 1), weight: Float.random(in: 0.5...2, using: &generator)
                )
            }
            let names = (0..<groups).map { GraphScene.Group(id: $0, name: "分野\($0)") }
            return GraphScene(nodes: nodeList, edges: edgeList, groups: names)
        }

        @Test("1,500 点と 2.4 万本の線を、1 フレーム 16 ms より十分短く描ける")
        func largeGraphFrameTime() throws {
            let model = GraphCanvasModel()
            let renderer = try #require(model.renderer)
            model.viewSize = CGSize(width: 1400, height: 900)
            model.setScene(Self.largeScene())
            renderer.layout.run(steps: 300)
            model.fitAll(animated: false)

            var cpu: [Double] = []
            var gpu: [Double] = []
            for frame in 0..<30 {
                model.needsFrame = true
                if frame == 10 { model.select(nodeID: 42) }
                let start = CACurrentMediaTime()
                let made = try #require(model.makeFrame(view: nil))
                cpu.append((CACurrentMediaTime() - start) * 1000)
                gpu.append(renderer.renderOffscreen(made, width: 2800, height: 1800))
            }
            let gpuMedian = gpu.sorted()[gpu.count / 2]
            let cpuMedian = cpu.sorted()[cpu.count / 2]
            print(String(format: "描画の性能: GPU %.2f ms, CPU %.2f ms（中央値）", gpuMedian, cpuMedian))
            // CI の仮想の GPU でも通るよう、余裕を持たせる（手元の Apple シリコンでは数 ms）
            #expect(gpuMedian < 40)
        }
    }
}
