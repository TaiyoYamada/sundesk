//
//  GraphRenderer+Draw.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import MetalKit

/// 描画のパイプライン（シェーダーの組み合わせと、色の重ね方）。
struct GraphPipelines {
    let project: any MTLComputePipelineState
    let background: any MTLRenderPipelineState
    let splat: any MTLRenderPipelineState
    let edge: any MTLRenderPipelineState
    let node: any MTLRenderPipelineState
    let label: any MTLRenderPipelineState

    static let pixelFormat = MTLPixelFormat.bgra8Unorm
    static let densityFormat = MTLPixelFormat.rgba16Float

    init(device: any MTLDevice, library: any MTLLibrary) throws {
        guard let project = library.makeFunction(name: "projectNodes") else { throw GraphLayoutError.noDevice }
        self.project = try device.makeComputePipelineState(function: project)
        func pipeline(
            _ vertex: String, _ fragment: String, format: MTLPixelFormat = Self.pixelFormat, additive: Bool = false
        )
            throws -> any MTLRenderPipelineState
        {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
            attachment.isBlendingEnabled = true
            // 乗算済みのアルファで重ねる（アルファが 0 なら足し算になり、光が重なって明るくなる）
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        background = try pipeline("fullscreenVertex", "backgroundFragment")
        splat = try pipeline("splatVertex", "splatFragment", format: Self.densityFormat, additive: true)
        edge = try pipeline("edgeVertex", "edgeFragment")
        node = try pipeline("nodeVertex", "nodeFragment")
        label = try pipeline("labelVertex", "labelFragment")
    }
}

/// 描く先（画面か、テストでは画像）。
struct GraphRenderTarget {
    let pass: MTLRenderPassDescriptor
    let drawable: (any MTLDrawable)?
    /// 画素の大きさ。
    let size: CGSize
}

extension GraphRenderer {
    static let edgeVertexCount = 26  // (12 区間 + 1) × 2

    func encode(_ frame: GraphFrame, target: GraphRenderTarget, into commandBuffer: any MTLCommandBuffer) {
        var uniforms = frame.uniforms
        guard nodeCount > 0 else {
            encodeEmpty(target: target, uniforms: &uniforms, into: commandBuffer)
            return
        }
        encodeProjection(uniforms: &uniforms, into: commandBuffer)
        layout.encode(steps: frame.layoutSteps, into: commandBuffer)
        if frame.drawsClouds {
            encodeDensity(size: target.size, uniforms: &uniforms, into: commandBuffer)
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: target.pass) else { return }
        if !frame.drawsClouds { uniforms.style.y = 0 }
        encoder.setRenderPipelineState(pipelines.background)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 0)
        encoder.setFragmentTexture(frame.drawsClouds ? densityTexture ?? emptyTexture : emptyTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encodeEdges(frame.edgeCount, uniforms: &uniforms, encoder: encoder)
        encodeNodes(uniforms: &uniforms, encoder: encoder)
        encodeLabels(uniforms: &uniforms, encoder: encoder)
        encoder.endEncoding()
        if let drawable = target.drawable { commandBuffer.present(drawable) }
    }

    /// 点を画面に写す（コンピュート）。
    func encodeProjection(uniforms: inout GraphUniforms, into commandBuffer: any MTLCommandBuffer) {
        guard let positions = layout.positionBuffer, let infoBuffer, let states = states.buffer,
            let projected = projected.buffer, let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return }
        var count = UInt32(nodeCount)
        encoder.setComputePipelineState(pipelines.project)
        encoder.setBuffer(positions, offset: 0, index: 0)
        encoder.setBuffer(infoBuffer, offset: 0, index: 1)
        encoder.setBuffer(states, offset: 0, index: 2)
        encoder.setBuffer(projected, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 4)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 5)
        let width = min(pipelines.project.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(
            MTLSize(width: nodeCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
    }

    /// 雲の濃さを、半分の解像度の画像に足し合わせる。
    private func encodeDensity(size: CGSize, uniforms: inout GraphUniforms, into commandBuffer: any MTLCommandBuffer) {
        let width = max(Int(size.width) / 2, 1)
        let height = max(Int(size.height) / 2, 1)
        if densityTexture?.width != width || densityTexture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: GraphPipelines.densityFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            densityTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let densityTexture, let projected = projected.buffer, let colorBuffer, let infoBuffer else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = densityTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipelines.splat)
        encoder.setVertexBuffer(projected, offset: 0, index: 0)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(infoBuffer, offset: 0, index: 2)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 3)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: nodeCount)
        encoder.endEncoding()
    }

    private func encodeEdges(_ count: Int, uniforms: inout GraphUniforms, encoder: any MTLRenderCommandEncoder) {
        guard let projected = projected.buffer, let colorBuffer, let infoBuffer, let centroids = centroids.buffer
        else { return }
        encoder.setRenderPipelineState(pipelines.edge)
        encoder.setVertexBuffer(projected, offset: 0, index: 1)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 2)
        encoder.setVertexBuffer(infoBuffer, offset: 0, index: 3)
        encoder.setVertexBuffer(centroids, offset: 0, index: 4)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 5)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 0)
        let visible = min(count, edges.count)
        if visible > 0, let edgeBuffer {
            encoder.setVertexBuffer(edgeBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: Self.edgeVertexCount, instanceCount: visible)
        }
        if !emphasisEdges.isEmpty, let buffer = emphasisEdges.buffer {
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: Self.edgeVertexCount,
                instanceCount: emphasisEdges.count)
        }
    }

    private func encodeNodes(uniforms: inout GraphUniforms, encoder: any MTLRenderCommandEncoder) {
        guard let order = order.buffer, let projected = projected.buffer, let colorBuffer, let states = states.buffer
        else { return }
        encoder.setRenderPipelineState(pipelines.node)
        encoder.setVertexBuffer(order, offset: 0, index: 0)
        encoder.setVertexBuffer(projected, offset: 0, index: 1)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 2)
        encoder.setVertexBuffer(states, offset: 0, index: 3)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 4)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: nodeCount)
    }

    private func encodeLabels(uniforms: inout GraphUniforms, encoder: any MTLRenderCommandEncoder) {
        guard !labels.isEmpty, let buffer = labels.buffer, let atlas else { return }
        encoder.setRenderPipelineState(pipelines.label)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlas.texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: labels.count)
    }

    /// 点がないときは背景だけ。
    private func encodeEmpty(
        target: GraphRenderTarget, uniforms: inout GraphUniforms, into commandBuffer: any MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: target.pass) else { return }
        uniforms.style.y = 0
        encoder.setRenderPipelineState(pipelines.background)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphUniforms>.stride, index: 0)
        encoder.setFragmentTexture(emptyTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable = target.drawable { commandBuffer.present(drawable) }
    }

    /// 画像に描いて、GPU の時間（ミリ秒）を返す（性能のテスト用）。
    func renderOffscreen(_ frame: GraphFrame, width: Int, height: Int) -> Double {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: GraphPipelines.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor), let commandBuffer = queue.makeCommandBuffer()
        else { return 0 }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        encode(
            frame, target: GraphRenderTarget(pass: pass, drawable: nil, size: CGSize(width: width, height: height)),
            into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000
    }

    /// 点を画面に写して、結果を読む（テスト用）。
    func runProjection(uniforms: GraphUniforms) -> [ProjectedNode] {
        var uniforms = uniforms
        guard let commandBuffer = queue.makeCommandBuffer() else { return [] }
        encodeProjection(uniforms: &uniforms, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return projected.read()
    }
}
