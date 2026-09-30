//
//  GraphLayout.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import Metal

/// 力学モデルの定数。シェーダーの `LayoutParams` と同じ並び。
struct LayoutParams: Equatable {
    var nodeCount: UInt32
    var repulsion: Float
    var attraction: Float
    var gravity: Float
    var damping: Float
    var maxStep: Float
    var alpha: Float
    /// これより遠い点からは反発を受けない（距離の 2 乗）。
    ///
    /// すべての点から反発を受けると、どこにもつながらない点が、固まりの全体に押されて遠くへ飛んでいき、
    /// 全体を画面に収めたときに固まりが小さくつぶれて見える（d3-force の distanceMax と同じ考え）。
    var cutoff2: Float
    /// 奥行きをつぶす割合（1 回あたり）。平面に戻すときだけ 0 より大きくする。
    var flatten: Float
    /// 同じまとまり（コミュニティ）の中心へ引く強さ。まとまりが混ざらず、雲の形が読みやすくなる。
    var cohesion: Float

    /// 理想の距離（点と点の間隔）。
    static let spacing: Float = 30

    static func standard(nodeCount: Int, alpha: Float, flatten: Float = 0) -> LayoutParams {
        LayoutParams(
            nodeCount: UInt32(nodeCount), repulsion: spacing * spacing, attraction: 1 / spacing, gravity: 0.05,
            damping: 0.6, maxStep: 20, alpha: alpha, cutoff2: (spacing * 8) * (spacing * 8), flatten: flatten,
            cohesion: 0.06)
    }
}

enum GraphLayoutError: Error {
    case noDevice
    case compileFailed(String)
}

/// 点の置き場所を、Metal のコンピュートシェーダーで少しずつ計算する（Fruchterman-Reingold 法、3 次元）。
///
/// 平面で見るときは奥行きを 0 にしておくので、力も平面の中だけで働く。奥行きを付けると、
/// 平面の配置が立体にほどけていく。
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
    /// 点ごとのまとまり（まとまりの中心へ引かないなら `noGroup`）。
    private(set) var groups: [UInt32] = []
    private var groupBuffer: (any MTLBuffer)?
    private var centroidBuffer: (any MTLBuffer)?
    static let noGroup = UInt32.max
    /// GPU が止まっている間に行う書き換え（ドラッグや奥行きの付け外し）。
    private var pending: [() -> Void] = []

    /// 温度。1 から始めて、落ち着くまで下げる。
    private(set) var alpha: Float = 1
    /// 奥行きをつぶす割合（平面に戻す途中だけ 0 より大きい）。
    private(set) var flatten: Float = 0
    static let alphaDecay: Float = 0.985
    static let alphaMin: Float = 0.01
    static let flattenRate: Float = 0.06

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

    /// - Parameter groups: 点ごとのまとまり（`noGroup` なら引かない）。nil ならどれも引かない。
    func load(_ scene: GraphScene, positions initial: [SIMD4<Float>], groups: [UInt32]? = nil) {
        nodeCount = scene.nodes.count
        alpha = 1
        current = 0
        pending = []
        guard nodeCount > 0 else {
            positions = []
            return
        }
        let adjacency = scene.adjacency
        positions = [makeBuffer(initial), makeBuffer(initial)]
        velocities = makeBuffer([SIMD4<Float>](repeating: .zero, count: nodeCount))
        offsets = makeBuffer(adjacency.offsets)
        neighbors = makeBuffer(adjacency.neighbors.isEmpty ? [0] : adjacency.neighbors)
        weights = makeBuffer(adjacency.weights.isEmpty ? [0] : adjacency.weights)
        pinned = makeBuffer([UInt8](repeating: 0, count: nodeCount))
        self.groups = groups ?? [UInt32](repeating: Self.noGroup, count: nodeCount)
        groupBuffer = makeBuffer(self.groups)
        let groupCount = Int(self.groups.filter { $0 != Self.noGroup }.max().map { $0 + 1 } ?? 1)
        centroidBuffer = makeBuffer([SIMD4<Float>](repeating: .zero, count: groupCount))
        updateCentroids()
    }

    /// まとまりの中心を、今の位置から計算し直す（フレームごと）。
    func updateCentroids() {
        guard let centroidBuffer else { return }
        let centroids = Self.centroids(of: readPositions(), groups: groups)
        let pointer = centroidBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: centroids.count)
        for (index, centroid) in centroids.enumerated() where index * 16 < centroidBuffer.length {
            pointer[index] = centroid
        }
    }

    /// まとまりごとの位置の平均（w は点の数）。
    static func centroids(of positions: [SIMD4<Float>], groups: [UInt32]) -> [SIMD4<Float>] {
        let count = Int(groups.filter { $0 != noGroup }.max().map { $0 + 1 } ?? 1)
        var sums = [SIMD4<Float>](repeating: .zero, count: max(count, 1))
        for (position, group) in zip(positions, groups) where group != noGroup {
            sums[Int(group)] += SIMD4(position.xyz, 1)
        }
        return sums.map { $0.w > 0 ? SIMD4($0.xyz / $0.w, $0.w) : .zero }
    }

    /// もう一度動かす（点を動かしたときなど）。
    func reheat(to value: Float = 0.3) {
        alpha = max(alpha, value)
    }

    /// 奥行きを付ける（平面の配置を、立体にほどく）か、平面に戻す。
    func setDepth(_ enabled: Bool) {
        if enabled {
            flatten = 0
            schedule { [weak self] in self?.seedDepth() }
            reheat(to: 0.8)
        } else {
            flatten = Self.flattenRate
            reheat(to: 0.5)
        }
    }

    /// 奥行きがほとんどなければ、点ごとに少しずらす（すべて 0 だと、奥行きの方向に力が働かない）。
    private func seedDepth() {
        let current = readPositions()
        guard current.map({ abs($0.z) }).max() ?? 0 < LayoutParams.spacing * 0.5 else { return }
        var generator = SeededGenerator(seed: 0xDE97)
        let depths = current.map { _ in Float.random(in: -1...1, using: &generator) * LayoutParams.spacing * 4 }
        for buffer in positions {
            let pointer = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: nodeCount)
            for index in 0..<nodeCount { pointer[index].z = depths[index] }
        }
    }

    /// 書き換えを予約する。GPU が位置を読み書きしていない間（`applyPending()`）に行う。
    func schedule(_ mutation: @escaping () -> Void) {
        pending.append(mutation)
    }

    /// 予約した書き換えを行う。前のフレームの計算が終わってから呼ぶ。
    func applyPending() {
        let mutations = pending
        pending = []
        for mutation in mutations { mutation() }
    }

    /// 計算を `steps` 回進める命令を積む。
    func encode(steps: Int, into commandBuffer: any MTLCommandBuffer) {
        guard nodeCount > 0, let velocities, let offsets, let neighbors, let weights, let pinned, let groupBuffer,
            let centroidBuffer
        else { return }
        for _ in 0..<steps where !isSettled {
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
            var params = LayoutParams.standard(nodeCount: nodeCount, alpha: alpha, flatten: flatten)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(positions[current], offset: 0, index: 0)
            encoder.setBuffer(velocities, offset: 0, index: 1)
            encoder.setBuffer(positions[1 - current], offset: 0, index: 2)
            encoder.setBuffer(offsets, offset: 0, index: 3)
            encoder.setBuffer(neighbors, offset: 0, index: 4)
            encoder.setBuffer(weights, offset: 0, index: 5)
            encoder.setBuffer(pinned, offset: 0, index: 6)
            encoder.setBytes(&params, length: MemoryLayout<LayoutParams>.stride, index: 7)
            encoder.setBuffer(groupBuffer, offset: 0, index: 8)
            encoder.setBuffer(centroidBuffer, offset: 0, index: 9)
            let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
            encoder.dispatchThreads(
                MTLSize(width: nodeCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            encoder.endEncoding()
            current = 1 - current
            alpha *= Self.alphaDecay
        }
        if isSettled { flatten = 0 }
    }

    /// 計算を進めて、終わるまで待つ（テスト用）。1 回ごとに、まとまりの中心を計算し直す。
    func run(steps: Int) {
        applyPending()
        for _ in 0..<steps {
            updateCentroids()
            guard let commandBuffer = queue.makeCommandBuffer() else { return }
            encode(steps: 1, into: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }

    /// 今の位置を読む（GPU と共有したメモリから直接読む）。
    func readPositions() -> [SIMD4<Float>] {
        guard let buffer = positionBuffer else { return [] }
        let pointer = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: nodeCount)
        return Array(UnsafeBufferPointer(start: pointer, count: nodeCount))
    }

    /// 点を置き直して固定する（ドラッグ）。`position` が nil なら固定を外す。
    func pin(_ index: Int, at position: SIMD3<Float>?) {
        guard index < nodeCount else { return }
        schedule { [weak self] in
            guard let self, let pinned = self.pinned else { return }
            pinned.contents().storeBytes(of: position == nil ? 0 : 1, toByteOffset: index, as: UInt8.self)
            guard let position else { return }
            for buffer in self.positions {
                buffer.contents().storeBytes(
                    of: SIMD4(position, 0), toByteOffset: index * MemoryLayout<SIMD4<Float>>.stride,
                    as: SIMD4<Float>.self)
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
        positions: [SIMD4<Float>], velocities: inout [SIMD4<Float>], scene: GraphScene, params: LayoutParams,
        groups: [UInt32]? = nil
    ) -> [SIMD4<Float>] {
        let adjacency = scene.adjacency
        let groups = groups ?? [UInt32](repeating: GraphLayoutEngine.noGroup, count: positions.count)
        let centroids = GraphLayoutEngine.centroids(of: positions, groups: groups)
        var next = positions
        for index in positions.indices {
            let position = positions[index].xyz
            var force = SIMD3<Float>.zero
            for other in positions.indices where other != index {
                let delta = position - positions[other].xyz
                let distance2 = max((delta * delta).sum(), 0.01)
                guard distance2 <= params.cutoff2 else { continue }
                force += delta * (params.repulsion / distance2)
            }
            for edge in Int(adjacency.offsets[index])..<Int(adjacency.offsets[index + 1]) {
                let delta = positions[Int(adjacency.neighbors[edge])].xyz - position
                force += delta * (((delta * delta).sum()).squareRoot() * params.attraction * adjacency.weights[edge])
            }
            force -= position * params.gravity
            if groups[index] != GraphLayoutEngine.noGroup {
                force += (centroids[Int(groups[index])].xyz - position) * params.cohesion
            }
            if params.flatten > 0 { force.z = 0 }
            var velocity = (velocities[index].xyz + force * params.alpha) * params.damping
            let speed = ((velocity * velocity).sum()).squareRoot()
            if speed > params.maxStep { velocity *= params.maxStep / speed }
            velocity.z *= 1 - params.flatten
            velocities[index] = SIMD4(velocity, 0)
            var moved = position + velocity
            moved.z *= 1 - params.flatten
            next[index] = SIMD4(moved, 0)
        }
        return next
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
