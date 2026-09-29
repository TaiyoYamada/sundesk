//
//  GraphRenderer.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import MetalKit

/// 描画に渡す定数（シェーダーの `Uniforms` と同じ並び）。
struct GraphUniforms {
    var viewportSize: SIMD2<Float>
    var center: SIMD2<Float>
    var zoom: Float
    var nodeScale: Float
    var selected: Int32
    var padding: Int32 = 0
    var ringColor: SIMD4<Float>
}

/// 知識グラフを MTKView に描く。フレームごとにレイアウトを少し進めてから、線と点を描く。
final class GraphRenderer: NSObject, MTKViewDelegate {
    let device: any MTLDevice
    let layout: GraphLayoutEngine
    private let queue: any MTLCommandQueue
    private let edgePipeline: any MTLRenderPipelineState
    private let nodePipeline: any MTLRenderPipelineState

    private var edgeBuffer: (any MTLBuffer)?
    private var edgeColorBuffer: (any MTLBuffer)?
    private var radiusBuffer: (any MTLBuffer)?
    private var colorBuffer: (any MTLBuffer)?
    private var edgeCount = 0

    /// 描く前に呼ばれる（カメラと選択を読む）。
    var uniformsProvider: (() -> GraphUniforms)?
    /// 描いた後に呼ばれる（ラベルの位置を更新する）。
    var didDraw: (() -> Void)?

    init?(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
            let library = try? device.makeLibrary(source: GraphShaders.source, options: nil),
            let layout = try? GraphLayoutEngine(device: device, library: library),
            let edgePipeline = Self.pipeline(device, library, vertex: "edgeVertex", fragment: "edgeFragment"),
            let nodePipeline = Self.pipeline(device, library, vertex: "nodeVertex", fragment: "nodeFragment")
        else { return nil }
        self.device = device
        self.queue = queue
        self.layout = layout
        self.edgePipeline = edgePipeline
        self.nodePipeline = nodePipeline
    }

    private static func pipeline(
        _ device: any MTLDevice, _ library: any MTLLibrary, vertex: String, fragment: String
    ) -> (any MTLRenderPipelineState)? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// 形（点と線）を入れ替える。
    func load(_ scene: GraphScene, positions: [SIMD2<Float>]) {
        layout.load(scene, positions: positions)
        edgeCount = scene.edges.count
        edgeBuffer = makeBuffer(scene.edges.map { SIMD2<UInt32>(UInt32($0.source), UInt32($0.target)) })
        radiusBuffer = makeBuffer(scene.nodes.map(\.radius))
    }

    /// 色を入れ替える（選択や検索で、目立たせる点が変わったとき）。
    func updateColors(nodes: [SIMD4<Float>], edges: [SIMD4<Float>]) {
        colorBuffer = makeBuffer(nodes)
        edgeColorBuffer = makeBuffer(edges)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        layout.encode(steps: 2, into: commandBuffer)

        if let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        {
            if var uniforms = uniformsProvider?(), let positions = layout.positionBuffer, let colorBuffer,
                let radiusBuffer
            {
                if edgeCount > 0, let edgeBuffer, let edgeColorBuffer {
                    encoder.setRenderPipelineState(edgePipeline)
                    encoder.setVertexBuffer(positions, offset: 0, index: 0)
                    encoder.setVertexBuffer(edgeBuffer, offset: 0, index: 1)
                    encoder.setVertexBuffer(edgeColorBuffer, offset: 0, index: 2)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 3)
                    encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: edgeCount * 2)
                }
                encoder.setRenderPipelineState(nodePipeline)
                encoder.setVertexBuffer(positions, offset: 0, index: 0)
                encoder.setVertexBuffer(radiusBuffer, offset: 0, index: 1)
                encoder.setVertexBuffer(colorBuffer, offset: 0, index: 2)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 3)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 0)
                encoder.drawPrimitives(
                    type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: layout.nodeCount)
            }
            encoder.endEncoding()
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        didDraw?()
    }

    private func makeBuffer<T>(_ values: [T]) -> (any MTLBuffer)? {
        guard !values.isEmpty else { return nil }
        return values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
    }
}
