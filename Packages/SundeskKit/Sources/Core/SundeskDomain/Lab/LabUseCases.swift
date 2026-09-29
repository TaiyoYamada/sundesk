//
//  LabUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - 覗く

public protocol TokenizeUseCase: Sendable {
    func callAsFunction(_ prompt: LabPrompt) async throws(LabError) -> [TokenPiece]
}

public protocol PredictNextTokenUseCase: Sendable {
    func callAsFunction(_ prompt: LabPrompt, topK: Int, temperature: Double) async throws(LabError)
        -> NextTokenDistribution
}

public protocol GenerateWithProbabilitiesUseCase: Sendable {
    func callAsFunction(
        _ prompt: LabPrompt, settings: SamplingSettings, adapter: Adapter?
    ) -> AsyncThrowingStream<LabGenerationEvent, any Error>
}

public protocol InspectAttentionUseCase: Sendable {
    func callAsFunction(_ prompt: LabPrompt, layer: Int) async throws(LabError) -> AttentionMap
}

public protocol LogitLensUseCase: Sendable {
    func callAsFunction(_ prompt: LabPrompt, topK: Int) async throws(LabError) -> LogitLens
}

public protocol InspectActivationsUseCase: Sendable {
    func callAsFunction(activationsOf prompt: LabPrompt) async throws(LabError) -> ActivationNorms
}

// MARK: - いじる

public protocol TrainLoRAUseCase: Sendable {
    /// Vault の `folder` の下のノート（空なら全部）で LoRA を学習し、できたアダプタを記録する。
    func callAsFunction(
        model: String, folder: String, name: String, settings: LoRASettings
    ) -> AsyncThrowingStream<LoRAEvent, any Error>
}

public protocol SteerUseCase: Sendable {
    func callAsFunction(
        _ prompt: LabPrompt, steering: SteeringSetup, settings: SamplingSettings
    ) async throws(LabError) -> (vector: SteeringVector, comparison: SteeringComparison)
}

// MARK: - 記録

public protocol LabRecordsUseCase: Sendable {
    func experiments() async throws(LabError) -> [Experiment]
    func deleteExperiment(_ id: UUID) async throws(LabError)
    func adapters() async throws(LabError) -> [Adapter]
    func deleteAdapter(_ adapter: Adapter) async throws(LabError)
    func changes() -> AsyncStream<Void>
}

/// 実験室の画面が使うもの一式。
public typealias LabUseCases = TokenizeUseCase & PredictNextTokenUseCase & GenerateWithProbabilitiesUseCase
    & InspectAttentionUseCase & LogitLensUseCase & InspectActivationsUseCase & TrainLoRAUseCase & SteerUseCase
    & LabRecordsUseCase

/// 実験室の操作。エンジンで計算し、軽い情報（モデル、プロンプト、設定、結果の要約）を毎回記録する。
public struct LabInteractor: LabUseCases {
    private let engine: any LabEngine
    private let records: any LabRecordRepository
    private let vault: any VaultRepository
    private let markdown: any MarkdownParsing
    private let files: any LabFileLocations

    public init(
        engine: any LabEngine, records: any LabRecordRepository, vault: any VaultRepository,
        markdown: any MarkdownParsing, files: any LabFileLocations
    ) {
        self.engine = engine
        self.records = records
        self.vault = vault
        self.markdown = markdown
        self.files = files
    }

    public func callAsFunction(_ prompt: LabPrompt) async throws(LabError) -> [TokenPiece] {
        let tokens = try await engine.tokenize(prompt)
        await record(.tokenize, prompt, [:], "\(tokens.count) トークン")
        return tokens
    }

    public func callAsFunction(
        _ prompt: LabPrompt, topK: Int, temperature: Double
    ) async throws(LabError) -> NextTokenDistribution {
        let distribution = try await engine.nextToken(prompt, topK: topK, temperature: temperature)
        let top = distribution.tokens.first.map { "「\($0.text)」\(Self.percent($0.probability))" } ?? "なし"
        await record(
            .nextToken, prompt, ["温度": "\(temperature)"],
            "最有力 \(top)、エントロピー \(String(format: "%.2f", distribution.entropy))")
        return distribution
    }

    public func callAsFunction(
        _ prompt: LabPrompt, settings: SamplingSettings, adapter: Adapter?
    ) -> AsyncThrowingStream<LabGenerationEvent, any Error> {
        let engine = engine
        return AsyncThrowingStream { continuation in
            let task = Task {
                var text = ""
                do {
                    for try await event in engine.generate(
                        prompt, settings: settings, alternatives: 5, adapter: adapter?.path)
                    {
                        if case .token(let token) = event { text += token.token.text }
                        continuation.yield(event)
                    }
                    var parameters = Self.parameters(settings)
                    if let adapter { parameters["LoRA"] = adapter.name }
                    await record(.generate, prompt, parameters, String(text.prefix(200)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func callAsFunction(_ prompt: LabPrompt, layer: Int) async throws(LabError) -> AttentionMap {
        let map = try await engine.attention(prompt, layer: layer)
        await record(.attention, prompt, ["層": "\(layer)"], "\(map.tokens.count) トークン、\(map.headCount) ヘッド")
        return map
    }

    public func callAsFunction(_ prompt: LabPrompt, topK: Int) async throws(LabError) -> LogitLens {
        let lens = try await engine.logitLens(prompt, topK: topK)
        let final = lens.layers.last?.last?.first.map { "「\($0.text)」" } ?? "なし"
        await record(.logitLens, prompt, [:], "\(lens.layers.count) 層、最後の予測 \(final)")
        return lens
    }

    public func callAsFunction(activationsOf prompt: LabPrompt) async throws(LabError) -> ActivationNorms {
        let norms = try await engine.activations(prompt)
        await record(.activations, prompt, [:], "\(norms.norms.count) 層 × \(norms.tokens.count) トークン")
        return norms
    }

    public func callAsFunction(
        model: String, folder: String, name: String, settings: LoRASettings
    ) -> AsyncThrowingStream<LoRAEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let texts = try await NoteTexts.read(in: folder, vault: vault, markdown: markdown)
                    guard texts.count >= 2 else {
                        throw LabError.engine("学習に使えるノートが足りません（2 本以上必要です）")
                    }
                    let path = files.newAdapterDirectory(name: name)
                    var lastLoss: Double?
                    for try await event in engine.trainLoRA(
                        model: model, texts: texts, adapterPath: path, settings: settings)
                    {
                        if case .progress(_, _, let loss) = event { lastLoss = loss }
                        if case .validation(_, let loss) = event { lastLoss = loss }
                        continuation.yield(event)
                    }
                    let adapter = Adapter(
                        id: UUID(), name: name, model: model, path: path, settings: settings,
                        source: folder.isEmpty ? "すべてのノート（\(texts.count) 本）" : "\(folder)（\(texts.count) 本）",
                        finalLoss: lastLoss, createdAt: .now)
                    try await records.save(adapter)
                    await record(
                        .lora, LabPrompt(model: model, text: adapter.source, chatTemplate: false),
                        ["反復": "\(settings.iterations)", "ランク": "\(settings.rank)", "学習率": "\(settings.learningRate)"],
                        "「\(name)」を作成" + (lastLoss.map { String(format: "、損失 %.3f", $0) } ?? ""))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func callAsFunction(
        _ prompt: LabPrompt, steering: SteeringSetup, settings: SamplingSettings
    ) async throws(LabError) -> (vector: SteeringVector, comparison: SteeringComparison) {
        let vector = try await engine.steeringVector(
            model: prompt.model, layer: steering.layer, positive: steering.positive, negative: steering.negative)
        let comparison = try await engine.steer(prompt, vector: vector, strength: steering.strength, settings: settings)
        let parameters = [
            "層": "\(steering.layer)", "強さ": "\(steering.strength)",
            "正": steering.positive.joined(separator: " / "), "負": steering.negative.joined(separator: " / "),
        ]
        await record(.steering, prompt, parameters, String(comparison.steered.prefix(200)))
        return (vector, comparison)
    }

    // MARK: 記録

    public func experiments() async throws(LabError) -> [Experiment] {
        try await records.experiments()
    }

    public func deleteExperiment(_ id: UUID) async throws(LabError) {
        try await records.deleteExperiment(id)
    }

    public func adapters() async throws(LabError) -> [Adapter] {
        try await records.adapters()
    }

    public func deleteAdapter(_ adapter: Adapter) async throws(LabError) {
        try await records.deleteAdapter(adapter.id)
        files.remove(adapter.path)
    }

    public func changes() -> AsyncStream<Void> {
        records.changes()
    }

    // MARK: 内部

    private func record(_ kind: Experiment.Kind, _ prompt: LabPrompt, _ parameters: [String: String], _ summary: String)
        async
    {
        var parameters = parameters
        if prompt.chatTemplate { parameters["チャット形式"] = "はい" }
        try? await records.save(
            Experiment(kind: kind, model: prompt.model, prompt: prompt.text, parameters: parameters, summary: summary))
    }

    static func parameters(_ settings: SamplingSettings) -> [String: String] {
        var parameters = [
            "温度": "\(settings.temperature)", "top-p": "\(settings.topP)", "最大トークン": "\(settings.maxTokens)",
        ]
        if settings.topK > 0 { parameters["top-k"] = "\(settings.topK)" }
        if let seed = settings.seed { parameters["種"] = "\(seed)" }
        return parameters
    }

    static func percent(_ probability: Double) -> String {
        String(format: "%.1f%%", probability * 100)
    }
}

// MARK: - モデルの管理

public protocol ModelManagementUseCase: Sendable {
    func localModels() async throws(LabError) -> [LocalModel]
    func download(_ id: String) -> AsyncThrowingStream<DownloadEvent, any Error>
    func delete(_ id: String) async throws(LabError)
    func loadedModels() async throws(LabError) -> LoadedModels
    func unload(_ kind: ModelKind?) async throws(LabError)
}

public struct ModelManagementInteractor: ModelManagementUseCase {
    private let repository: any ModelRepository
    private let files: any LabFileLocations

    public init(repository: any ModelRepository, files: any LabFileLocations) {
        self.repository = repository
        self.files = files
    }

    public func localModels() async throws(LabError) -> [LocalModel] {
        try await repository.localModels().sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func download(_ id: String) -> AsyncThrowingStream<DownloadEvent, any Error> {
        repository.download(id.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Hugging Face のキャッシュのモデルはエンジンで消し、工房で作ったモデル（絶対パス）はフォルダを消す。
    public func delete(_ id: String) async throws(LabError) {
        if id.hasPrefix("/") {
            try? await repository.unload(nil)
            files.remove(id)
        } else {
            try await repository.delete(id)
        }
    }

    public func loadedModels() async throws(LabError) -> LoadedModels {
        try await repository.loadedModels()
    }

    public func unload(_ kind: ModelKind?) async throws(LabError) {
        try await repository.unload(kind)
    }
}

// MARK: - 画像生成

public protocol ImageGenerationUseCase: Sendable {
    func models() async throws(LabError) -> [ImageModelOption]
    /// 生成して記録する。
    func generate(_ request: ImageRequest) -> AsyncThrowingStream<ImageGenerationEvent, any Error>
    func images() async throws(LabError) -> [GeneratedImage]
    func delete(_ image: GeneratedImage) async throws(LabError)
    func changes() -> AsyncStream<Void>
}

public struct ImageGenerationInteractor: ImageGenerationUseCase {
    private let engine: any ImageEngine
    private let records: any LabRecordRepository
    private let files: any LabFileLocations

    public init(engine: any ImageEngine, records: any LabRecordRepository, files: any LabFileLocations) {
        self.engine = engine
        self.records = records
        self.files = files
    }

    public func models() async throws(LabError) -> [ImageModelOption] {
        try await engine.imageModels()
    }

    public func generate(_ request: ImageRequest) -> AsyncThrowingStream<ImageGenerationEvent, any Error> {
        let engine = engine
        let records = records
        let path = files.newImagePath()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in engine.generate(request, outputPath: path) {
                        if case .done(let image) = event { try await records.save(image) }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func images() async throws(LabError) -> [GeneratedImage] {
        try await records.images()
    }

    public func delete(_ image: GeneratedImage) async throws(LabError) {
        try await records.deleteImage(image.id)
        files.remove(image.path)
    }

    public func changes() -> AsyncStream<Void> {
        records.changes()
    }
}
