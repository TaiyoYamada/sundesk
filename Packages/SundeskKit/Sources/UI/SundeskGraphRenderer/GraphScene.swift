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
        /// まとまり（コミュニティ）の番号。0 から大きい順に振ると、大きいまとまりほど見分けやすい色になる。
        public let group: Int
        /// 生まれた時（0〜1。ノートを作った順）。nil なら、時間を再生しても最初からある。
        public let birth: Float?

        public init(id: Int, label: String, radius: Float, group: Int, birth: Float? = nil) {
            self.id = id
            self.label = label
            self.radius = radius
            self.group = group
            self.birth = birth
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

    /// まとまりの名前（遠くから眺めたときに、固まりの上に出す）。
    public struct Group: Equatable, Sendable {
        public let id: Int
        public let name: String

        public init(id: Int, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let nodes: [Node]
    public let edges: [Edge]
    public let groups: [Group]

    public init(nodes: [Node], edges: [Edge], groups: [Group] = []) {
        self.nodes = nodes
        self.edges = edges.filter {
            $0.source != $0.target && nodes.indices.contains($0.source) && nodes.indices.contains($0.target)
        }
        self.groups = groups
    }

    public static let empty = GraphScene(nodes: [], edges: [])

    /// まとまりをまたぐ線の、ばねの強さの倍率。
    static let crossGroupSpring: Float = 0.3

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
    /// まとまりをまたぐ線は弱くして、まとまりどうしが混ざらないようにする。
    var adjacency: Adjacency {
        var degrees = [Int](repeating: 0, count: nodes.count)
        for edge in edges {
            degrees[edge.source] += 1
            degrees[edge.target] += 1
        }
        var lists = [[(UInt32, Float)]](repeating: [], count: nodes.count)
        for edge in edges {
            let across: Float = nodes[edge.source].group == nodes[edge.target].group ? 1 : Self.crossGroupSpring
            let weight = edge.weight * across / Float(max(min(degrees[edge.source], degrees[edge.target]), 1))
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

    /// 最初の置き場所。種を固定した乱数で円の中に散らす（同じグラフなら同じ形になる）。奥行きは 0。
    func initialPositions(spacing: Float) -> [SIMD4<Float>] {
        var generator = SeededGenerator(seed: 0x5EED)
        let radius = spacing * Float(nodes.count).squareRoot() * 0.8
        return nodes.map { _ in
            let angle = Float.random(in: 0..<(2 * .pi), using: &generator)
            let distance = radius * Float.random(in: 0...1, using: &generator).squareRoot()
            return SIMD4(cos(angle) * distance, sin(angle) * distance, 0, 0)
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
