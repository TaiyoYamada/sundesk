//
//  GraphCanvasModel.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Observation
import QuartzCore
import simd

/// 知識グラフの描画の状態（形、カメラ、選択、経路、時間の再生）。View と Metal の描画をつなぐ。
///
/// フレームごとの計算（カメラの動き、点の寄せ方、ラベルの置き場所）は `makeFrame` で行う。
/// SwiftUI に知らせる値（選んだ点の画面の位置など）は、変わったときだけ書き換える。
@MainActor
@Observable
public final class GraphCanvasModel {
    public private(set) var scene = GraphScene.empty
    /// 選んでいる点の ID。
    public private(set) var selectedNodeID: Int?
    /// 目立たせる点の ID（検索に一致したものなど）。
    public var highlightedNodeIDs: Set<Int> = [] {
        didSet { if highlightedNodeIDs != oldValue { emphasisDidChange() } }
    }
    /// 経路（たどる順の点の ID）。空なら経路を出さない。
    public private(set) var pathNodeIDs: [Int] = []
    /// 奥行きをつけて見ているか。
    public private(set) var is3D = false
    /// 時間の再生の位置（0〜1）。nil なら再生していない（すべてを出す）。
    public internal(set) var timelineCursor: Double?
    public internal(set) var isPlayingTimeline = false
    /// 再生の位置までに生まれた点の数。
    public internal(set) var visibleNodeCount = 0
    /// 選んだ点の画面の位置（SwiftUI の座標）。画面の外なら nil。
    public internal(set) var selectionAnchor: CGPoint?
    /// 選んだ点の半径（pt）。
    public internal(set) var selectionRadius: Double = 0
    /// 選んだ点のそばに、出てくるノートを出す濃さ（0〜1。近づくほど 1）。
    public internal(set) var noteDetail: Double = 0
    /// Metal が使えないとき false。
    public private(set) var isAvailable = true

    /// 点が選ばれたとき（空いているところを押したら nil）。
    @ObservationIgnored public var onSelect: ((Int?) -> Void)?
    /// 点をダブルクリックしたか、選んだ点で Return を押したとき（その概念が出てくるノートを開く）。
    @ObservationIgnored public var onOpen: ((Int) -> Void)?
    /// ⇧ を押しながら点を押したとき（選んでいる点からの経路をたどる）。nil なら経路を消す（Esc）。
    @ObservationIgnored public var onPathTarget: ((Int?) -> Void)?

    @ObservationIgnored let renderer: GraphRenderer?
    /// 描いている View（キーボードの操作を受けさせるため）。
    @ObservationIgnored weak var view: NSView?
    @ObservationIgnored var camera = GraphCamera()
    @ObservationIgnored var flight: (flight: CameraFlight, start: Double)?
    /// 配置が落ち着くまで、全体が収まるようにカメラを合わせ続ける。拡大や移動をしたらやめる。
    @ObservationIgnored var followsLayout = false
    /// 飛び終わったら、配置が落ち着くまでカメラを合わせる（奥行きを付け外ししたとき）。
    @ObservationIgnored var followsAfterFlight = false
    /// 奥行きを付けた直後に、ゆっくり回して立体だと分かるようにする（始めた時刻）。
    @ObservationIgnored var spinStart: Double?
    @ObservationIgnored var indexByID: [Int: Int] = [:]
    /// 点ごとの隣（重い線の順）。
    @ObservationIgnored var neighborIndices: [[Int]] = []
    @ObservationIgnored var edgeWeights: [Int64: Float] = [:]
    @ObservationIgnored var info: [NodeInfo] = []
    /// まとまりの ID → まとまりの添字（0 から詰めた番号）。
    @ObservationIgnored var groupIndexByID: [Int: Int] = [:]
    @ObservationIgnored var groupSizes: [Int] = []
    /// 名前のあるまとまり（添字、名前の文字の地図の番号）。
    @ObservationIgnored var namedGroups: [(group: Int, entry: Int)] = []
    /// 重要な順の点の添字。
    @ObservationIgnored var importanceOrder: [Int] = []
    @ObservationIgnored var states: [NodeState] = []
    @ObservationIgnored var lensVelocities: [Float] = []
    @ObservationIgnored var lensTargets: Set<Int> = []
    /// 選んだときの拡大の度合い（隣を並べる円の大きさの基準）。
    @ObservationIgnored var lensZoom: Float?
    @ObservationIgnored var emphasized: [Int: Float] = [:]
    @ObservationIgnored var positions: [SIMD4<Float>] = []
    @ObservationIgnored var projected: [ProjectedNode] = []
    @ObservationIgnored var centroids: [SIMD4<Float>] = []
    @ObservationIgnored var labelPlacer = LabelPlacer()
    @ObservationIgnored var hoveredIndex: Int?
    @ObservationIgnored var selectionTime: Double?
    /// 選んでいるものがあるときに 1 へ近づく（周りを薄くする度合い）。
    @ObservationIgnored var focusAmount: Float = 0
    @ObservationIgnored var isDark = false
    @ObservationIgnored var pixelScale: Float = 2
    @ObservationIgnored var lastFrameTime = CACurrentMediaTime()
    @ObservationIgnored let clockStart = CACurrentMediaTime()
    /// 次のフレームを描く必要があるか（カメラや色が変わった）。
    @ObservationIgnored var needsFrame = true
    @ObservationIgnored var emphasisNeedsUpdate = true
    @ObservationIgnored var labelsAreSettled = true
    @ObservationIgnored var orderIsFlat = false
    @ObservationIgnored var emphasisChangedSinceOrder = true

    public init() {
        renderer = GraphRenderer()
        isAvailable = renderer != nil
        renderer?.frameProvider = { [weak self] view in self?.makeFrame(view: view) }
    }

    var viewSize: CGSize {
        get { CGSize(width: CGFloat(camera.viewSize.x), height: CGFloat(camera.viewSize.y)) }
        set {
            camera.viewSize = SIMD2(Float(max(newValue.width, 1)), Float(max(newValue.height, 1)))
            needsFrame = true
        }
    }

    // MARK: - 形

    public func setScene(_ scene: GraphScene) {
        guard scene != self.scene else { return }
        if isSameShape(scene) {
            // 生まれた時だけが変わった（育った順を後から読んだ）。配置はそのまま
            self.scene = scene
            rebuildIndices()
            renderer?.updateInfo(info)
            needsFrame = true
            return
        }
        self.scene = scene
        rebuildIndices()
        if let selectedNodeID, indexByID[selectedNodeID] == nil { self.selectedNodeID = nil }
        pathNodeIDs = pathNodeIDs.filter { indexByID[$0] != nil }
        let positions = scene.initialPositions(spacing: LayoutParams.spacing)
        states = [NodeState](repeating: NodeState(), count: scene.nodes.count)
        lensVelocities = [Float](repeating: 0, count: scene.nodes.count)
        lensTargets = []
        hoveredIndex = nil
        labelPlacer.reset()
        renderer?.load(
            scene, positions: positions, info: info,
            groups: info.map { $0.w > 0 ? UInt32($0.z) : GraphLayoutEngine.noGroup })
        renderer?.loadLabels(
            scene.nodes.map { ($0.label, LabelAtlas.Style.concept) }
                + namedGroups.map { (scene.groups[$0.entry].name, LabelAtlas.Style.group) })
        if is3D { renderer?.layout.setDepth(true) }
        self.positions = positions
        camera.center = .zero
        let radius = LayoutParams.spacing * Float(max(scene.nodes.count, 1)).squareRoot() * 0.8
        camera.zoom = max(min(camera.viewSize.x, camera.viewSize.y) / (radius * 2.6), 0.02)
        followsLayout = true
        flight = nil
        updateColors()
        emphasisDidChange()
    }

    /// 点と線が同じで、生まれた時だけが違うか。
    private func isSameShape(_ other: GraphScene) -> Bool {
        other.edges == scene.edges && other.groups == scene.groups && other.nodes.count == scene.nodes.count
            && zip(other.nodes, scene.nodes).allSatisfy {
                $0.id == $1.id && $0.label == $1.label && $0.radius == $1.radius && $0.group == $1.group
            }
    }

    /// 点を選ぶ。nil なら選択を外す。画面の端にあれば、見えるところへ動かす。
    public func select(nodeID: Int?) {
        guard selectedNodeID != nodeID else { return }
        selectedNodeID = nodeID
        selectionTime = nodeID == nil ? nil : CACurrentMediaTime()
        lensZoom = nodeID == nil ? nil : camera.zoom
        if let nodeID { reveal(nodeID) }
        emphasisDidChange()
    }

    /// 経路を出す（たどる順の点の ID）。経路の全体が見えるようにカメラを動かす。
    public func setPath(_ nodeIDs: [Int]) {
        let path = nodeIDs.filter { indexByID[$0] != nil }
        guard path != pathNodeIDs else { return }
        pathNodeIDs = path
        emphasisDidChange()
        let points = path.compactMap { indexByID[$0] }.map { positions[$0].xyz }
        if points.count >= 2 { fly(to: camera.fitting(points, margin: 0.6)) }
    }

    /// 奥行きをつける／平面に戻す。配置は立体にほどけ（平面につぶれ）、カメラも斜めから（正面から）見る向きへ回る。
    public func setDepth(_ enabled: Bool) {
        guard enabled != is3D else { return }
        is3D = enabled
        renderer?.layout.setDepth(enabled)
        var target = camera
        target.perspective = enabled ? 1 : 0
        target.yaw = enabled ? 0.55 : 0
        target.pitch = enabled ? -0.42 : 0
        followsLayout = false
        flight = (CameraFlight(from: camera, to: target, duration: 1.3), CACurrentMediaTime())
        spinStart = enabled ? CACurrentMediaTime() + 1.3 : nil
        followsAfterFlight = true
        needsFrame = true
    }

    /// キーボードの操作（矢印、Esc、Return）をグラフで受ける。
    public func focusKeyboard() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }

    /// 点の配置をもう一度動かす。
    public func reheat() {
        renderer?.layout.reheat(to: 0.5)
        needsFrame = true
    }

    var isSettled: Bool { renderer?.layout.isSettled ?? true }

    func setAppearance(isDark: Bool, pixelScale: Float) {
        self.pixelScale = pixelScale
        guard self.isDark != isDark else {
            needsFrame = true
            return
        }
        self.isDark = isDark
        updateColors()
    }

    func updateColors() {
        guard let renderer, !scene.nodes.isEmpty else { return }
        renderer.updateColors(scene.nodes.map { GraphPalette.color(for: $0.group, isDark: isDark) })
        needsFrame = true
    }

    /// 強調するもの（選択、経路、検索の一致、ホバー）が変わった。
    func emphasisDidChange() {
        emphasisNeedsUpdate = true
        needsFrame = true
    }
}
