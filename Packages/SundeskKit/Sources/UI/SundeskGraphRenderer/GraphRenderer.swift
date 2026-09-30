//
//  GraphRenderer.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import MetalKit

/// 線のデータ（シェーダーの `EdgeData` と同じ並び）。
struct EdgeData: Equatable {
    var source: UInt32
    var target: UInt32
    /// 0〜1。
    var weight: Float
    /// 0 = ふつう、1 = 選んだ点の隣、2 = 経路。
    var kind: Float
}

/// 1 フレームで描くもの（CPU で決めて、描画に渡す）。
struct GraphFrame {
    var uniforms: GraphUniforms
    /// 配置の計算を進める回数。
    var layoutSteps: Int
    /// 雲を描くか（遠くから眺めているときだけ）。
    var drawsClouds: Bool
    /// 描く線の数（重い順）。
    var edgeCount: Int
}

/// 知識グラフを MTKView に描く。
///
/// フレームごとに、前のフレームの計算が終わるのを待ってから、CPU で決めたもの（カメラ、点の状態、ラベル）を書き、
/// 点を画面に写し、背景 → 雲 → 線 → 点 → 文字の順に描いて、最後に配置を少し進める。
final class GraphRenderer: NSObject, MTKViewDelegate {
    let device: any MTLDevice
    let layout: GraphLayoutEngine
    let queue: any MTLCommandQueue
    let pipelines: GraphPipelines

    private(set) var nodeCount = 0
    private(set) var edges: [EdgeData] = []
    private(set) var infoBuffer: (any MTLBuffer)?
    private(set) var colorBuffer: (any MTLBuffer)?
    private(set) var edgeBuffer: (any MTLBuffer)?
    let states = DynamicBuffer<NodeState>()
    let projected = DynamicBuffer<ProjectedNode>()
    let order = DynamicBuffer<UInt32>()
    let centroids = DynamicBuffer<SIMD4<Float>>()
    let emphasisEdges = DynamicBuffer<EdgeData>()
    let labels = DynamicBuffer<LabelInstance>()
    private(set) var atlas: LabelAtlas?
    var densityTexture: (any MTLTexture)?
    /// 雲を描かないときに、代わりに渡す 1 画素の画像。
    private(set) var emptyTexture: (any MTLTexture)?

    /// フレームごとに呼ばれる（CPU の計算をして、描くものを返す）。nil なら描かずに休む。
    var frameProvider: ((MTKView) -> GraphFrame?)?
    /// 描いた後に呼ばれる。
    var didDraw: (() -> Void)?
    private var inFlight: (any MTLCommandBuffer)?
    private var frameCount = 0
    /// GPU の 1 フレームの時間（ミリ秒、ならした値）。
    private(set) var gpuMilliseconds: Double = 0
    /// CPU の 1 フレームの時間（ミリ秒、ならした値）。
    private(set) var cpuMilliseconds: Double = 0

    init?(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
            let library = try? device.makeLibrary(source: GraphShaders.source, options: nil),
            let layout = try? GraphLayoutEngine(device: device, library: library),
            let pipelines = try? GraphPipelines(device: device, library: library)
        else { return nil }
        self.device = device
        self.queue = queue
        self.layout = layout
        self.pipelines = pipelines
        super.init()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: GraphPipelines.densityFormat, width: 1, height: 1, mipmapped: false)
        emptyTexture = device.makeTexture(descriptor: descriptor)
        for buffer in [states, projected, order, centroids, emphasisEdges, labels] as [any DynamicBufferProtocol] {
            buffer.device = device
        }
    }

    /// 形（点と線）を入れ替える。線は重い順に並べる（遠くからは重い線だけを描く）。
    func load(_ scene: GraphScene, positions: [SIMD4<Float>], info: [NodeInfo], groups: [UInt32]) {
        waitForGPU()
        layout.load(scene, positions: positions, groups: groups)
        nodeCount = scene.nodes.count
        let range = scene.edges.map(\.weight).reduce(into: (Float.infinity, -Float.infinity)) {
            $0 = (min($0.0, $1), max($0.1, $1))
        }
        let span = max(range.1 - range.0, 1e-6)
        edges = scene.edges.sorted { $0.weight > $1.weight }.map {
            EdgeData(
                source: UInt32($0.source), target: UInt32($0.target),
                weight: range.1 > range.0 ? ($0.weight - range.0) / span : 0.5, kind: 0)
        }
        edgeBuffer = makeBuffer(edges)
        infoBuffer = makeBuffer(info)
        states.write([NodeState](repeating: NodeState(), count: nodeCount))
        projected.write([ProjectedNode](repeating: .zero, count: nodeCount))
        order.write((0..<UInt32(nodeCount)).map(\.self))
    }

    /// 文字の地図を作り直す。
    func loadLabels(_ labels: [(text: String, style: LabelAtlas.Style)]) {
        atlas = labels.isEmpty ? nil : LabelAtlas(device: device, queue: queue, labels: labels)
    }

    /// 点ごとの変わらない値だけを入れ替える（配置はそのまま）。
    func updateInfo(_ info: [NodeInfo]) {
        waitForGPU()
        infoBuffer = makeBuffer(info)
    }

    func updateColors(_ colors: [SIMD4<Float>]) {
        waitForGPU()
        colorBuffer = makeBuffer(colors)
    }

    /// 前のフレームの計算が終わるまで待つ（CPU が共有のバッファを書き換える前に）。
    func waitForGPU() {
        inFlight?.waitUntilCompleted()
        inFlight = nil
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        densityTexture = nil
    }

    func draw(in view: MTKView) {
        waitForGPU()
        layout.applyPending()
        if !layout.isSettled { layout.updateCentroids() }
        let start = CFAbsoluteTimeGetCurrent()
        guard let frame = frameProvider?(view), let commandBuffer = queue.makeCommandBuffer(),
            let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable
        else { return }
        cpuMilliseconds = cpuMilliseconds * 0.9 + (CFAbsoluteTimeGetCurrent() - start) * 1000 * 0.1
        let target = GraphRenderTarget(pass: pass, drawable: drawable, size: view.drawableSize)
        encode(frame, target: target, into: commandBuffer)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            DispatchQueue.main.async { self?.recordGPUTime(milliseconds) }
        }
        commandBuffer.commit()
        inFlight = commandBuffer
        didDraw?()
    }

    private func recordGPUTime(_ milliseconds: Double) {
        gpuMilliseconds = gpuMilliseconds * 0.9 + milliseconds * 0.1
        frameCount += 1
        if Self.logsStatistics, frameCount % 120 == 0 {
            let line = String(
                format: "graph: GPU %.2f ms, CPU %.2f ms, 点 %d, 線 %d\n", gpuMilliseconds, cpuMilliseconds, nodeCount,
                edges.count)
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// 環境変数 `SUNDESK_GRAPH_STATS` があれば、フレームの時間を書き出す（性能を測るとき）。
    private static let logsStatistics = ProcessInfo.processInfo.environment["SUNDESK_GRAPH_STATS"] != nil

    func makeBuffer<T>(_ values: [T]) -> (any MTLBuffer)? {
        guard !values.isEmpty else { return nil }
        return values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
    }
}

protocol DynamicBufferProtocol: AnyObject {
    var device: (any MTLDevice)? { get set }
}

/// フレームごとに書き換えるバッファ。足りなくなったら大きく作り直す。
final class DynamicBuffer<Element>: DynamicBufferProtocol {
    var device: (any MTLDevice)?
    private(set) var buffer: (any MTLBuffer)?
    private(set) var count = 0
    var isEmpty: Bool { count < 1 }

    func write(_ values: [Element]) {
        count = values.count
        let length = max(values.count, 1) * MemoryLayout<Element>.stride
        if buffer == nil || buffer!.length < length {
            buffer = device?.makeBuffer(length: max(length, 256) * 3 / 2, options: .storageModeShared)
        }
        guard let buffer, !values.isEmpty else { return }
        values.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
    }

    /// 書いた値を読む（テストと、GPU の結果を読むとき）。
    func read() -> [Element] {
        guard let buffer, !isEmpty else { return [] }
        let pointer = buffer.contents().bindMemory(to: Element.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}
