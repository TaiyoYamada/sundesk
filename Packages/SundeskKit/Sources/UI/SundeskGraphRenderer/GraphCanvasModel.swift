//
//  GraphCanvasModel.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Observation
import simd

/// 知識グラフの描画の状態（形、カメラ、選択）。View と Metal の描画をつなぐ。
@MainActor
@Observable
public final class GraphCanvasModel {
    public private(set) var scene = GraphScene.empty
    /// 選んでいる点の ID。
    public private(set) var selectedNodeID: Int?
    /// 目立たせる点の ID（検索に一致したものなど）。
    public var highlightedNodeIDs: Set<Int> = [] {
        didSet { if highlightedNodeIDs != oldValue { updateColors() } }
    }
    /// 点が選ばれたとき（空いているところを押したら nil）。
    @ObservationIgnored public var onSelect: ((Int?) -> Void)?

    /// ラベルを描き直すきっかけ（描画のたびに増える）。
    private(set) var frame = 0
    /// Metal が使えないとき false。
    public private(set) var isAvailable = true

    @ObservationIgnored let renderer: GraphRenderer?
    @ObservationIgnored private var center = SIMD2<Float>.zero
    @ObservationIgnored private var zoom: Float = 1
    @ObservationIgnored var viewSize = CGSize(width: 800, height: 600)
    @ObservationIgnored private var indexByID: [Int: Int] = [:]
    @ObservationIgnored private var neighborIndices: [[Int]] = []
    @ObservationIgnored private var appearanceIsDark = false

    public init() {
        renderer = GraphRenderer()
        isAvailable = renderer != nil
        renderer?.uniformsProvider = { [weak self] in self?.uniforms() ?? Self.emptyUniforms }
        renderer?.didDraw = { [weak self] in self?.frame &+= 1 }
    }

    private static let emptyUniforms = GraphUniforms(
        viewportSize: [1, 1], center: .zero, zoom: 1, nodeScale: 1, selected: -1, ringColor: [0, 0, 0, 1])

    // MARK: - 形

    public func setScene(_ scene: GraphScene) {
        guard scene != self.scene else { return }
        self.scene = scene
        indexByID = Dictionary(scene.nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        neighborIndices = [[Int]](repeating: [], count: scene.nodes.count)
        for edge in scene.edges {
            neighborIndices[edge.source].append(edge.target)
            neighborIndices[edge.target].append(edge.source)
        }
        if let selectedNodeID, indexByID[selectedNodeID] == nil { self.selectedNodeID = nil }
        let positions = scene.initialPositions(spacing: LayoutParams.spacing)
        renderer?.load(scene, positions: positions)
        center = .zero
        let radius = LayoutParams.spacing * Float(max(scene.nodes.count, 1)).squareRoot() * 0.8
        zoom = Float(min(viewSize.width, viewSize.height)) / (radius * 2.6)
        updateColors()
    }

    /// 点を選ぶ。nil なら選択を外す。
    public func select(nodeID: Int?) {
        guard selectedNodeID != nodeID else { return }
        selectedNodeID = nodeID
        updateColors()
    }

    /// 点を画面の中央に持ってくる。
    public func focus(on nodeID: Int) {
        guard let index = indexByID[nodeID], let position = positions()[safe: index] else { return }
        center = position
        zoom = max(zoom, 1.2)
    }

    /// すべての点が収まるようにする。
    public func fitAll() {
        let positions = positions()
        guard let first = positions.first else { return }
        var lower = first
        var upper = first
        for position in positions {
            lower = simd_min(lower, position)
            upper = simd_max(upper, position)
        }
        center = (lower + upper) / 2
        let extent = simd_max(upper - lower, [1, 1])
        zoom = min(Float(viewSize.width) / extent.x, Float(viewSize.height) / extent.y) * 0.9
    }

    /// 点の配置をもう一度動かす。
    public func reheat() {
        renderer?.layout.reheat(to: 0.5)
    }

    var isSettled: Bool { renderer?.layout.isSettled ?? true }

    // MARK: - 座標

    func positions() -> [SIMD2<Float>] {
        renderer?.layout.readPositions() ?? []
    }

    /// View の座標（左下が原点）を、グラフの座標にする。
    func world(at point: CGPoint) -> SIMD2<Float> {
        let offset = SIMD2(Float(point.x - viewSize.width / 2), Float(point.y - viewSize.height / 2))
        return center + offset / zoom
    }

    /// グラフの座標を、SwiftUI の座標（左上が原点）にする。
    func screen(_ position: SIMD2<Float>) -> CGPoint {
        let offset = (position - center) * zoom
        return CGPoint(x: viewSize.width / 2 + CGFloat(offset.x), y: viewSize.height / 2 - CGFloat(offset.y))
    }

    /// 押した場所にある点（添字）。
    func hitTest(_ point: CGPoint) -> Int? {
        let target = world(at: point)
        let positions = positions()
        var best: (index: Int, distance: Float)?
        for (index, position) in positions.enumerated() {
            let radius = (scene.nodes[index].radius * nodeScale + 4) / zoom
            let distance = simd_distance(position, target)
            if distance <= radius, distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    // MARK: - 操作

    func pan(by delta: CGSize) {
        center -= SIMD2(Float(delta.width), Float(delta.height)) / zoom
    }

    func zoom(by factor: CGFloat, around point: CGPoint) {
        let anchor = world(at: point)
        zoom = min(max(zoom * Float(factor), 0.02), 20)
        let offset = SIMD2(Float(point.x - viewSize.width / 2), Float(point.y - viewSize.height / 2))
        center = anchor - offset / zoom
    }

    func click(at point: CGPoint) {
        let nodeID = hitTest(point).map { scene.nodes[$0].id }
        select(nodeID: nodeID)
        onSelect?(nodeID)
    }

    func drag(node index: Int, to point: CGPoint) {
        renderer?.layout.pin(index, at: world(at: point))
    }

    func release(node index: Int) {
        renderer?.layout.pin(index, at: nil)
    }

    func setAppearance(isDark: Bool) {
        guard appearanceIsDark != isDark else { return }
        appearanceIsDark = isDark
        updateColors()
    }

    // MARK: - ラベル

    struct Label: Identifiable {
        let id: Int
        let text: String
        let point: CGPoint
        let isEmphasized: Bool
    }

    /// 画面に出すラベル。大きい点（中心的な概念）と、選んだ点とその隣、目立たせる点。
    func labels(limit: Int = 40) -> [Label] {
        _ = frame
        let positions = positions()
        guard positions.count == scene.nodes.count else { return [] }
        let selectedIndex = selectedNodeID.flatMap { indexByID[$0] }
        var emphasized = Set(highlightedNodeIDs.compactMap { indexByID[$0] })
        if let selectedIndex {
            emphasized.insert(selectedIndex)
            emphasized.formUnion(neighborIndices[selectedIndex])
        }
        let largest = scene.nodes.indices.sorted { scene.nodes[$0].radius > scene.nodes[$1].radius }.prefix(limit)
        let bounds = CGRect(origin: .zero, size: viewSize).insetBy(dx: -40, dy: -20)
        return Set(largest).union(emphasized).compactMap { index in
            let node = scene.nodes[index]
            var point = screen(positions[index])
            point.y += CGFloat(node.radius * nodeScale) + 9
            guard bounds.contains(point) else { return nil }
            return Label(id: node.id, text: node.label, point: point, isEmphasized: emphasized.contains(index))
        }
    }

    // MARK: - 色

    private var nodeScale: Float { min(max(zoom, 0.5), 2).squareRoot() }

    private func uniforms() -> GraphUniforms {
        let ring: SIMD4<Float> = appearanceIsDark ? [1, 1, 1, 1] : [0.1, 0.1, 0.1, 1]
        return GraphUniforms(
            viewportSize: [Float(viewSize.width), Float(viewSize.height)], center: center, zoom: zoom,
            nodeScale: nodeScale, selected: Int32(selectedNodeID.flatMap { indexByID[$0] } ?? -1), ringColor: ring)
    }

    private func updateColors() {
        guard let renderer, !scene.nodes.isEmpty else { return }
        let selectedIndex = selectedNodeID.flatMap { indexByID[$0] }
        var focus = Set(highlightedNodeIDs.compactMap { indexByID[$0] })
        if let selectedIndex {
            focus.insert(selectedIndex)
            focus.formUnion(neighborIndices[selectedIndex])
        }
        let isFocused = !focus.isEmpty
        let nodes = scene.nodes.enumerated().map { index, node in
            var color = GraphPalette.color(for: node.group)
            color.w = !isFocused || focus.contains(index) ? 0.95 : 0.18
            return color
        }
        let base: SIMD4<Float> = appearanceIsDark ? [0.8, 0.8, 0.85, 1] : [0.35, 0.35, 0.4, 1]
        let edges = scene.edges.map { edge -> SIMD4<Float> in
            var color = base
            if let selectedIndex, edge.source == selectedIndex || edge.target == selectedIndex {
                color.w = 0.7
            } else {
                color.w = isFocused ? 0.04 : 0.14
            }
            return color
        }
        renderer.updateColors(nodes: nodes, edges: edges)
    }
}

/// コミュニティごとの色（システムの色に近い配色）。
enum GraphPalette {
    static let colors: [SIMD4<Float>] = [
        [0.0, 0.48, 1.0, 1], [1.0, 0.58, 0.0, 1], [0.2, 0.78, 0.35, 1], [1.0, 0.18, 0.33, 1],
        [0.69, 0.32, 0.87, 1], [0.35, 0.78, 0.98, 1], [1.0, 0.8, 0.0, 1], [0.64, 0.52, 0.37, 1],
        [0.35, 0.34, 0.84, 1], [0.0, 0.78, 0.75, 1], [1.0, 0.39, 0.51, 1], [0.56, 0.56, 0.58, 1],
    ]

    static func color(for group: Int) -> SIMD4<Float> {
        colors[((group % colors.count) + colors.count) % colors.count]
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
