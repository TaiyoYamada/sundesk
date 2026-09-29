//
//  GraphScene.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 描くグラフ。点は配列の添字で指す。
public struct GraphScene: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public let id: Int
        public let label: String
        /// 点の半径（画面上のポイント）。
        public let radius: Float
        /// 色の番号（コミュニティ）。
        public let group: Int

        public init(id: Int, label: String, radius: Float, group: Int) {
            self.id = id
            self.label = label
            self.radius = radius
            self.group = group
        }
    }

    public struct Edge: Equatable, Sendable {
        public let source: Int
        public let target: Int
        /// ばねの強さ（0.5〜2 くらい）。
        public let weight: Float

        public init(source: Int, target: Int, weight: Float) {
            self.source = source
            self.target = target
            self.weight = weight
        }
    }

    public let nodes: [Node]
    public let edges: [Edge]

    public init(nodes: [Node], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges.filter {
            $0.source != $0.target && nodes.indices.contains($0.source) && nodes.indices.contains($0.target)
        }
    }

    public static let empty = GraphScene(nodes: [], edges: [])

    /// 点ごとの隣接（CSR 形式）。両方向に持つ。
    struct Adjacency {
        /// 点 i の隣は `neighbors[offsets[i]..<offsets[i + 1]]`。
        let offsets: [UInt32]
        let neighbors: [UInt32]
        let weights: [Float]
    }

    ///
    /// ばねの強さは、両端の点の次数の小さいほうで割る（d3-force と同じ）。
    /// 割らないと、つながりの多い点ほど強く引かれ、よくつながった固まりが 1 点につぶれる。
    var adjacency: Adjacency {
        var degrees = [Int](repeating: 0, count: nodes.count)
        for edge in edges {
            degrees[edge.source] += 1
            degrees[edge.target] += 1
        }
        var lists = [[(UInt32, Float)]](repeating: [], count: nodes.count)
        for edge in edges {
            let weight = edge.weight / Float(max(min(degrees[edge.source], degrees[edge.target]), 1))
            lists[edge.source].append((UInt32(edge.target), weight))
            lists[edge.target].append((UInt32(edge.source), weight))
        }
        var offsets: [UInt32] = [0]
        var neighbors: [UInt32] = []
        var weights: [Float] = []
        for list in lists {
            neighbors += list.map(\.0)
            weights += list.map(\.1)
            offsets.append(UInt32(neighbors.count))
        }
        return Adjacency(offsets: offsets, neighbors: neighbors, weights: weights)
    }

    /// 最初の置き場所。種を固定した乱数で円の中に散らす（同じグラフなら同じ形になる）。
    func initialPositions(spacing: Float) -> [SIMD2<Float>] {
        var generator = SeededGenerator(seed: 0x5EED)
        let radius = spacing * Float(nodes.count).squareRoot() * 0.8
        return nodes.map { _ in
            let angle = Float.random(in: 0..<(2 * .pi), using: &generator)
            let distance = radius * Float.random(in: 0...1, using: &generator).squareRoot()
            return SIMD2(cos(angle), sin(angle)) * distance
        }
    }
}

/// 種を固定できる乱数（SplitMix64）。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
