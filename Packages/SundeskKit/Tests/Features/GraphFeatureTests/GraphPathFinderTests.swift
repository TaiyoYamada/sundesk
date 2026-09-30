//
//  GraphPathFinderTests.swift
//  GraphFeatureTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Testing

@testable import GraphFeature

@MainActor
@Suite("経路をたどる")
struct GraphPathFinderTests {
    @Test("いちばん歩数の少ない道をたどる")
    func shortestPath() {
        // 0 - 1 - 2 - 3 と、0 - 4 - 3 の近道
        let edges = [
            GraphEdgeItem(source: 0, target: 1, weight: 1), GraphEdgeItem(source: 1, target: 2, weight: 1),
            GraphEdgeItem(source: 2, target: 3, weight: 1), GraphEdgeItem(source: 0, target: 4, weight: 1),
            GraphEdgeItem(source: 4, target: 3, weight: 1),
        ]

        #expect(GraphPathFinder.path(from: 0, to: 3, nodeCount: 5, edges: edges) == [0, 4, 3])
        #expect(GraphPathFinder.path(from: 3, to: 0, nodeCount: 5, edges: edges) == [3, 4, 0])
    }

    @Test("同じ歩数なら、強い関係を通る道を選ぶ")
    func prefersStrongEdges() {
        let edges = [
            GraphEdgeItem(source: 0, target: 1, weight: 0.5), GraphEdgeItem(source: 1, target: 3, weight: 0.5),
            GraphEdgeItem(source: 0, target: 2, weight: 2), GraphEdgeItem(source: 2, target: 3, weight: 2),
        ]

        #expect(GraphPathFinder.path(from: 0, to: 3, nodeCount: 4, edges: edges) == [0, 2, 3])
    }

    @Test("つながっていなければ nil、同じ点や範囲の外も nil")
    func unreachable() {
        let edges = [GraphEdgeItem(source: 0, target: 1, weight: 1)]

        #expect(GraphPathFinder.path(from: 0, to: 2, nodeCount: 3, edges: edges) == nil)
        #expect(GraphPathFinder.path(from: 0, to: 0, nodeCount: 3, edges: edges) == nil)
        #expect(GraphPathFinder.path(from: 0, to: 9, nodeCount: 3, edges: edges) == nil)
    }
}
