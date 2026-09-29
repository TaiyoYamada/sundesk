//
//  EngineLabGateway.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SundeskEngineClient

/// モデルの管理、LLM を覗く・いじる計算、画像生成を、Python のエンジンに頼む（docs/engine-api.md）。
public struct EngineLabGateway: ModelRepository, LabEngine, ImageEngine {
    private let process: EngineProcess

    public init(process: EngineProcess) {
        self.process = process
    }

    // MARK: - モデルの管理

    public func localModels() async throws(LabError) -> [LocalModel] {
        let response: ModelsResponse = try await get("models")
        return response.models.map {
            LocalModel(id: $0.id, kind: ModelKind(rawValue: $0.kind) ?? .other, sizeBytes: $0.sizeBytes, path: $0.path)
        }
    }

    public func download(_ id: String) -> AsyncThrowingStream<DownloadEvent, any Error> {
        stream("models/download", body: DownloadRequest(id: id), as: DownloadLine.self) { line in
            switch line.type {
            case "progress": .progress(downloaded: line.downloadedBytes ?? 0, total: line.totalBytes)
            case "done": .done(path: line.path ?? "")
            default: nil
            }
        }
    }

    public func delete(_ id: String) async throws(LabError) {
        let client = try await client()
        _ = try await call { try await client.delete("models/\(id)", as: DeletedResponse.self) }
    }

    public func loadedModels() async throws(LabError) -> LoadedModels {
        let response: LoadedResponse = try await get("models/loaded")
        return LoadedModels(
            llm: response.llm, image: response.image, embedding: response.embedding, adapter: response.adapter)
    }

    public func unload(_ kind: ModelKind?) async throws(LabError) {
        let _: UnloadResponse = try await post("models/unload", UnloadRequest(kind: kind?.rawValue ?? "all"))
    }

    // MARK: - 覗く

    public func tokenize(_ prompt: LabPrompt) async throws(LabError) -> [TokenPiece] {
        let response: TokenizeResponse = try await post(
            "lab/tokenize", TokenizeRequest(model: prompt.model, text: prompt.text))
        return response.tokens.map { TokenPiece(id: $0.id, text: $0.text, start: $0.start, end: $0.end) }
    }

    public func nextToken(_ prompt: LabPrompt, topK: Int, temperature: Double) async throws(LabError)
        -> NextTokenDistribution
    {
        let response: NextTokenResponse = try await post(
            "lab/next-token",
            NextTokenRequest(
                model: prompt.model, prompt: prompt.text, chatTemplate: prompt.chatTemplate, topK: topK,
                temperature: temperature))
        return NextTokenDistribution(tokens: response.tokens.map(\.value), entropy: response.entropy)
    }

    public func generate(
        _ prompt: LabPrompt, settings: SamplingSettings, alternatives: Int, adapter: String?
    ) -> AsyncThrowingStream<LabGenerationEvent, any Error> {
        let request = GenerateRequest(
            model: prompt.model, prompt: prompt.text, chatTemplate: prompt.chatTemplate, maxTokens: settings.maxTokens,
            temperature: settings.temperature, topP: settings.topP, topK: settings.topK, seed: settings.seed,
            alternatives: alternatives, adapter: adapter)
        return stream("lab/generate", body: request, as: GenerateLine.self) { line in
            switch line.type {
            case "loading": .loading
            case "token":
                .token(
                    GeneratedToken(
                        token: TokenProbability(
                            id: line.id ?? 0, text: line.text ?? "", probability: line.probability ?? 0),
                        alternatives: (line.alternatives ?? []).map(\.value)))
            case "done": .done(tokensPerSecond: line.tokensPerSecond)
            default: nil
            }
        }
    }

    public func attention(_ prompt: LabPrompt, layer: Int) async throws(LabError) -> AttentionMap {
        let response: AttentionResponse = try await post(
            "lab/attention",
            LayerRequest(model: prompt.model, prompt: prompt.text, chatTemplate: prompt.chatTemplate, layer: layer))
        return AttentionMap(
            tokens: response.tokens.map(\.text), layerCount: response.numLayers, headCount: response.numHeads,
            layer: response.layer, heads: response.heads, mean: response.mean)
    }

    public func logitLens(_ prompt: LabPrompt, topK: Int) async throws(LabError) -> LogitLens {
        let response: LogitLensResponse = try await post(
            "lab/logit-lens",
            TopKRequest(model: prompt.model, prompt: prompt.text, chatTemplate: prompt.chatTemplate, topK: topK))
        return LogitLens(
            tokens: response.tokens.map(\.text),
            layers: response.layers.map { layer in layer.positions.map { $0.top.map(\.value) } })
    }

    public func activations(_ prompt: LabPrompt) async throws(LabError) -> ActivationNorms {
        let response: ActivationsResponse = try await post(
            "lab/activations",
            PromptRequest(model: prompt.model, prompt: prompt.text, chatTemplate: prompt.chatTemplate))
        return ActivationNorms(tokens: response.tokens.map(\.text), norms: response.norms)
    }

    // MARK: - いじる

    public func trainLoRA(
        model: String, texts: [String], adapterPath: String, settings: LoRASettings
    ) -> AsyncThrowingStream<LoRAEvent, any Error> {
        let request = LoRARequest(
            model: model, texts: texts, adapterPath: adapterPath, iterations: settings.iterations, rank: settings.rank,
            learningRate: settings.learningRate, batchSize: settings.batchSize,
            maxSeqLength: settings.maxSequenceLength, numLayers: settings.layerCount)
        return stream("lora/train", body: request, as: LoRALine.self) { line in
            switch line.type {
            case "loading": .loading
            case "progress":
                .progress(iteration: line.iteration ?? 0, total: line.total ?? 0, trainLoss: line.trainLoss ?? 0)
            case "validation": .validation(iteration: line.iteration ?? 0, loss: line.valLoss ?? 0)
            case "done": .done(adapterPath: line.adapterPath ?? adapterPath)
            default: nil
            }
        }
    }

    public func steeringVector(
        model: String, layer: Int, positive: [String], negative: [String]
    ) async throws(LabError) -> SteeringVector {
        let response: SteeringVectorResponse = try await post(
            "steering/vector", SteeringVectorRequest(model: model, layer: layer, positive: positive, negative: negative)
        )
        return SteeringVector(model: model, layer: response.layer, values: response.vector, norm: response.norm)
    }

    public func steer(
        _ prompt: LabPrompt, vector: SteeringVector, strength: Double, settings: SamplingSettings
    ) async throws(LabError) -> SteeringComparison {
        let response: SteeringResponse = try await post(
            "steering/generate",
            SteeringRequest(
                model: prompt.model, prompt: prompt.text, chatTemplate: prompt.chatTemplate, layer: vector.layer,
                vector: vector.values, strength: strength, maxTokens: settings.maxTokens,
                temperature: settings.temperature, seed: settings.seed ?? 0))
        return SteeringComparison(baseline: response.baseline, steered: response.steered)
    }

    // MARK: - 画像生成

    public func imageModels() async throws(LabError) -> [ImageModelOption] {
        let response: ImageModelsResponse = try await get("images/models")
        return response.models.map {
            ImageModelOption(
                id: $0.id, name: $0.name, repository: $0.repo, isDownloaded: $0.downloaded,
                defaultSteps: $0.defaultSteps,
                defaultSize: $0.defaultSize)
        }
    }

    public func generate(_ request: ImageRequest, outputPath: String) -> AsyncThrowingStream<
        ImageGenerationEvent, any Error
    > {
        let body = ImageGenerateRequest(
            model: request.model, prompt: request.prompt, width: request.width, height: request.height,
            steps: request.steps, seed: request.seed, quantize: request.quantize, outputPath: outputPath)
        return stream("images/generate", body: body, as: ImageLine.self) { line in
            switch line.type {
            case "loading": .loading
            case "progress": .progress(step: line.step ?? 0, total: line.total ?? 0)
            case "done":
                .done(
                    GeneratedImage(
                        id: UUID(), model: request.model, prompt: request.prompt, width: request.width,
                        height: request.height, steps: request.steps, seed: line.seed ?? 0,
                        path: line.path ?? outputPath, seconds: line.seconds ?? 0, createdAt: .now))
            default: nil
            }
        }
    }

    // MARK: - 内部

    private func client() async throws(LabError) -> EngineClient {
        do {
            return try await process.runningClient()
        } catch {
            throw .engine(EngineMapper.failure(from: error).message)
        }
    }

    private func get<Response: Decodable>(_ path: String) async throws(LabError) -> Response {
        let client = try await client()
        return try await call { try await client.get(path, as: Response.self) }
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, _ body: Body) async throws(LabError)
        -> Response
    {
        let client = try await client()
        return try await call { try await client.post(path, body: body, as: Response.self) }
    }

    private func call<T>(_ body: () async throws -> T) async throws(LabError) -> T {
        do {
            return try await body()
        } catch let error as EngineClientError {
            throw .engine(error.message)
        } catch {
            throw .engine(error.localizedDescription)
        }
    }

    /// NDJSON を読み、1 行ずつ Domain の出来事に直す（nil を返した行は捨てる）。
    private func stream<Body: Encodable & Sendable, Line: Decodable & Sendable, Event: Sendable>(
        _ path: String, body: Body, as type: Line.Type, map: @escaping @Sendable (Line) -> Event?
    ) -> AsyncThrowingStream<Event, any Error> {
        let process = process
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let client: EngineClient
                    do {
                        client = try await process.runningClient()
                    } catch let error as EngineProcessError {
                        throw LabError.engine(EngineMapper.failure(from: error).message)
                    }
                    for try await line in client.stream(path, body: body, as: Line.self) {
                        if let event = map(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch let error as EngineClientError {
                    continuation.finish(throwing: LabError.engine(error.message))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
