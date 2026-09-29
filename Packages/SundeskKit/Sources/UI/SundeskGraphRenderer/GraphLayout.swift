//
//  GraphLayout.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import Metal

/// 力学モデルの定数。
struct LayoutParams: Equatable {
    var nodeCount: UInt32
    var repulsion: Float
    var attraction: Float
    var gravity: Float
    var damping: Float
    var maxStep: Float
    var alpha: Float

    /// 理想の距離（点と点の間隔）。
    static let spacing: Float = 30

    static func standard(nodeCount: Int, alpha: Float) -> LayoutParams {
        LayoutParams(
            nodeCount: UInt32(nodeCount), repulsion: spacing * spacing, attraction: 1 / spacing, gravity: 0.02,
            damping: 0.6, maxStep: 20, alpha: alpha)
    }
}

enum GraphLayoutError: Error {
    case noDevice
    case compileFailed(String)
}

/// 点の置き場所を、Metal のコンピュートシェーダーで少しずつ計算する（Fruchterman-Reingold 法）。
///
/// 反発はすべての組について計算する（O(n²)。数千点なら GPU で 1 フレームに収まる）。
/// 位置は 2 つのバッファを交互に使い、1 回の計算の中では前の位置だけを読む（CPU の参照実装と結果をそろえるため）。
final class GraphLayoutEngine {
    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState

    private(set) var nodeCount = 0
    private var positions: [any MTLBuffer] = []
    private var current = 0
    private var velocities: (any MTLBuffer)?
    private var offsets: (any MTLBuffer)?
    private var neighbors: (any MTLBuffer)?
    private var weights: (any MTLBuffer)?
    private var pinned: (any MTLBuffer)?

    /// 温度。1 から始めて、落ち着くまで下げる。
    private(set) var alpha: Float = 1
    static let alphaDecay: Float = 0.985
    static let alphaMin: Float = 0.01

    init(device: any MTLDevice, library: any MTLLibrary) throws {
        guard let queue = device.makeCommandQueue(), let function = library.makeFunction(name: "layoutStep") else {
            throw GraphLayoutError.noDevice
        }
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    var isSettled: Bool { alpha < Self.alphaMin }

    /// 今の位置のバッファ（描画で読む）。
    var positionBuffer: (any MTLBuffer)? { positions.isEmpty ? nil : positions[current] }

    func load(_ scene: GraphScene, positions initial: [SIMD2<Float>]) {
        nodeCount = scene.nodes.count
        alpha = 1
        current = 0
        guard nodeCount > 0 else {
            positions = []
            return
        }
        let adjacency = scene.adjacency
        positions = [makeBuffer(initial), makeBuffer(initial)]
        velocities = makeBuffer([SIMD2<Float>](repeating: .zero, count: nodeCount))
        offsets = makeBuffer(adjacency.offsets)
        neighbors = makeBuffer(adjacency.neighbors.isEmpty ? [0] : adjacency.neighbors)
        weights = makeBuffer(adjacency.weights.isEmpty ? [0] : adjacency.weights)
        pinned = makeBuffer([UInt8](repeating: 0, count: nodeCount))
    }

    /// もう一度動かす（点を動かしたときなど）。
    func reheat(to value: Float = 0.3) {
        alpha = max(alpha, value)
    }

    /// 計算を `steps` 回進める命令を積む。
    func encode(steps: Int, into commandBuffer: any MTLCommandBuffer) {
        guard nodeCount > 0, let velocities, let offsets, let neighbors, let weights, let pinned else { return }
        for _ in 0..<steps where !isSettled {
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
            var params = LayoutParams.standard(nodeCount: nodeCount, alpha: alpha)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(positions[current], offset: 0, index: 0)
            encoder.setBuffer(velocities, offset: 0, index: 1)
            encoder.setBuffer(positions[1 - current], offset: 0, index: 2)
            encoder.setBuffer(offsets, offset: 0, index: 3)
            encoder.setBuffer(neighbors, offset: 0, index: 4)
            encoder.setBuffer(weights, offset: 0, index: 5)
            encoder.setBuffer(pinned, offset: 0, index: 6)
            encoder.setBytes(&params, length: MemoryLayout<LayoutParams>.stride, index: 7)
            let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
            encoder.dispatchThreads(
                MTLSize(width: nodeCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            encoder.endEncoding()
            current = 1 - current
            alpha *= Self.alphaDecay
        }
    }

    /// 計算を進めて、終わるまで待つ（テスト用）。
    func run(steps: Int) {
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        encode(steps: steps, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// 今の位置を読む（GPU と共有したメモリから直接読む）。
    func readPositions() -> [SIMD2<Float>] {
        guard let buffer = positionBuffer else { return [] }
        let pointer = buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: nodeCount)
        return Array(UnsafeBufferPointer(start: pointer, count: nodeCount))
    }

    /// 点を置き直して固定する（ドラッグ）。`position` が nil なら固定を外す。
    func pin(_ index: Int, at position: SIMD2<Float>?) {
        guard index < nodeCount, let pinned else { return }
        pinned.contents().storeBytes(of: position == nil ? 0 : 1, toByteOffset: index, as: UInt8.self)
        if let position {
            for buffer in positions {
                buffer.contents().storeBytes(
                    of: position, toByteOffset: index * MemoryLayout<SIMD2<Float>>.stride, as: SIMD2<Float>.self)
            }
        }
        reheat()
    }

    private func makeBuffer<T>(_ values: [T]) -> any MTLBuffer {
        values.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: max(bytes.count, 16), options: .storageModeShared)!
        }
    }
}

/// CPU での参照実装。GPU の計算が正しいかを確かめるのに使う。
enum GraphLayoutReference {
    static func step(
        positions: [SIMD2<Float>], velocities: inout [SIMD2<Float>], scene: GraphScene, params: LayoutParams
    ) -> [SIMD2<Float>] {
        let adjacency = scene.adjacency
        var next = positions
        for index in positions.indices {
            let position = positions[index]
            var force = SIMD2<Float>.zero
            for other in positions.indices where other != index {
                let delta = position - positions[other]
                force += delta * (params.repulsion / max((delta * delta).sum(), 0.01))
            }
            for edge in Int(adjacency.offsets[index])..<Int(adjacency.offsets[index + 1]) {
                let delta = positions[Int(adjacency.neighbors[edge])] - position
                force += delta * (((delta * delta).sum()).squareRoot() * params.attraction * adjacency.weights[edge])
            }
            force -= position * params.gravity
            var velocity = (velocities[index] + force * params.alpha) * params.damping
            let speed = ((velocity * velocity).sum()).squareRoot()
            if speed > params.maxStep { velocity *= params.maxStep / speed }
            velocities[index] = velocity
            next[index] = position + velocity
        }
        return next
    }
}
