//
//  LabUseCaseTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import Testing

@Suite("実験室")
struct LabUseCaseTests {
    private func makeLab(
        engine: LabEngineStub = LabEngineStub(), records: LabRecordsSpy = LabRecordsSpy(),
        files: [String: String] = ["数学/a.md": "固有値の本文", "数学/b.md": "行列の本文", "Swift/c.md": "actor"]
    ) -> LabInteractor {
        LabInteractor(
            engine: engine, records: records, vault: VaultStub(files: files), markdown: MarkdownParserStub(),
            files: FilesStub())
    }

    private let prompt = LabPrompt(model: "mlx-community/Qwen3-0.6B-4bit", text: "富士山は", chatTemplate: true)

    @Test("覗くたびに、モデル、プロンプト、設定、要約を記録する")
    func recordsExperiments() async throws {
        let records = LabRecordsSpy()
        let lab = makeLab(records: records)

        _ = try await lab(prompt)
        _ = try await lab(prompt, topK: 5, temperature: 0.8)
        _ = try await lab(prompt, layer: 3)

        let experiments = await records.saved
        #expect(experiments.map(\.kind) == [.tokenize, .nextToken, .attention])
        #expect(experiments[0].summary == "2 トークン")
        #expect(experiments[1].summary == "最有力 「日本」62.0%、エントロピー 1.20")
        #expect(experiments[1].parameters == ["温度": "0.8", "チャット形式": "はい"])
        #expect(experiments[2].parameters["層"] == "3")
    }

    @Test("生成は 1 トークンずつ流し、終わったら本文を記録する")
    func generationStreamsAndRecords() async throws {
        let records = LabRecordsSpy()
        let lab = makeLab(records: records)
        var texts: [String] = []

        for try await event in lab(prompt, settings: SamplingSettings(temperature: 0.5, seed: 7), adapter: nil) {
            if case .token(let token) = event { texts.append(token.token.text) }
        }

        #expect(texts == ["日本", "一"])
        let experiment = try #require(await records.saved.first)
        #expect(experiment.kind == .generate)
        #expect(experiment.summary == "日本一")
        #expect(experiment.parameters["種"] == "7")
    }

    @Test("LoRA はフォルダの下のノートの本文で学習し、アダプタを記録する")
    func trainsLoRA() async throws {
        let engine = LabEngineStub()
        let records = LabRecordsSpy()
        let lab = makeLab(engine: engine, records: records)

        for try await _ in lab(model: "m", folder: "数学", name: "数学の文体", settings: LoRASettings(iterations: 10)) {}

        #expect(await engine.trainedTexts.sorted() == ["固有値の本文", "行列の本文"])
        let adapter = try #require(await records.savedAdapters.first)
        #expect(adapter.name == "数学の文体")
        #expect(adapter.path == "/adapters/数学の文体")
        #expect(adapter.finalLoss == 1.5)
        #expect(adapter.source == "数学（2 本）")
    }

    @Test("学習に使えるノートが少なすぎたら断る")
    func refusesTooFewNotes() async {
        let lab = makeLab()

        await #expect(throws: LabError.engine("学習に使えるノートが足りません（2 本以上必要です）")) {
            for try await _ in lab(model: "m", folder: "Swift", name: "x", settings: LoRASettings()) {}
        }
    }

    @Test("画像を生成したら記録し、消すとファイルも消す")
    func imageGeneration() async throws {
        let records = LabRecordsSpy()
        let files = FilesStub()
        let generation = ImageGenerationInteractor(engine: LabEngineStub(), records: records, files: files)

        var events: [ImageGenerationEvent] = []
        for try await event in generation.generate(ImageRequest(model: "z-image-turbo", prompt: "猫")) {
            events.append(event)
        }

        #expect(events.count == 3)
        let image = try #require(await records.savedImages.first)
        #expect(image.path == "/images/new.png")
        try await generation.delete(image)
        #expect(await records.savedImages.isEmpty)
        #expect(files.removed.value == ["/images/new.png"])
    }
}

// MARK: - テスト用の偽物

actor LabEngineStub: LabEngine, ImageEngine {
    private(set) var trainedTexts: [String] = []

    func tokenize(_ prompt: LabPrompt) async throws(LabError) -> [TokenPiece] {
        [TokenPiece(id: 1, text: "富士", start: 0, end: 2), TokenPiece(id: 2, text: "山は", start: 2, end: 4)]
    }

    func nextToken(_ prompt: LabPrompt, topK: Int, temperature: Double) async throws(LabError) -> NextTokenDistribution
    {
        NextTokenDistribution(tokens: [TokenProbability(id: 3, text: "日本", probability: 0.62)], entropy: 1.2)
    }

    nonisolated func generate(
        _ prompt: LabPrompt, settings: SamplingSettings, alternatives: Int, adapter: String?
    ) -> AsyncThrowingStream<LabGenerationEvent, any Error> {
        AsyncThrowingStream { continuation in
            for text in ["日本", "一"] {
                continuation.yield(
                    .token(
                        GeneratedToken(token: TokenProbability(id: 0, text: text, probability: 0.5), alternatives: [])))
            }
            continuation.yield(.done(tokensPerSecond: 30))
            continuation.finish()
        }
    }

    func attention(_ prompt: LabPrompt, layer: Int) async throws(LabError) -> AttentionMap {
        AttentionMap(
            tokens: ["a", "b"], layerCount: 4, headCount: 2, layer: layer, heads: [], mean: [[1, 0], [0.5, 0.5]])
    }

    func logitLens(_ prompt: LabPrompt, topK: Int) async throws(LabError) -> LogitLens {
        LogitLens(tokens: [], layers: [])
    }

    func activations(_ prompt: LabPrompt) async throws(LabError) -> ActivationNorms {
        ActivationNorms(tokens: [], norms: [])
    }

    nonisolated func trainLoRA(
        model: String, texts: [String], adapterPath: String, settings: LoRASettings
    ) -> AsyncThrowingStream<LoRAEvent, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.record(texts)
                continuation.yield(.progress(iteration: 10, total: 10, trainLoss: 2.0))
                continuation.yield(.validation(iteration: 10, loss: 1.5))
                continuation.yield(.done(adapterPath: adapterPath))
                continuation.finish()
            }
        }
    }

    private func record(_ texts: [String]) {
        trainedTexts = texts
    }

    func steeringVector(model: String, layer: Int, positive: [String], negative: [String]) async throws(LabError)
        -> SteeringVector
    {
        SteeringVector(model: model, layer: layer, values: [1, 0], norm: 1)
    }

    func steer(_ prompt: LabPrompt, vector: SteeringVector, strength: Double, settings: SamplingSettings)
        async throws(LabError) -> SteeringComparison
    {
        SteeringComparison(baseline: "普通", steered: "嬉しい")
    }

    func imageModels() async throws(LabError) -> [ImageModelOption] { [] }

    nonisolated func generate(_ request: ImageRequest, outputPath: String) -> AsyncThrowingStream<
        ImageGenerationEvent, any Error
    > {
        AsyncThrowingStream { continuation in
            continuation.yield(.loading)
            continuation.yield(.progress(step: 1, total: 1))
            continuation.yield(
                .done(
                    GeneratedImage(
                        id: UUID(), model: request.model, prompt: request.prompt, width: 1024, height: 1024, steps: nil,
                        seed: 42, path: outputPath, seconds: 3, createdAt: .now)))
            continuation.finish()
        }
    }
}

actor LabRecordsSpy: LabRecordRepository {
    private(set) var saved: [Experiment] = []
    private(set) var savedAdapters: [Adapter] = []
    private(set) var savedImages: [GeneratedImage] = []

    func experiments() async throws(LabError) -> [Experiment] { saved }
    func save(_ experiment: Experiment) async throws(LabError) { saved.append(experiment) }
    func deleteExperiment(_ id: UUID) async throws(LabError) { saved.removeAll { $0.id == id } }
    func adapters() async throws(LabError) -> [Adapter] { savedAdapters }
    func save(_ adapter: Adapter) async throws(LabError) { savedAdapters.append(adapter) }
    func deleteAdapter(_ id: UUID) async throws(LabError) { savedAdapters.removeAll { $0.id == id } }
    func images() async throws(LabError) -> [GeneratedImage] { savedImages }
    func save(_ image: GeneratedImage) async throws(LabError) { savedImages.append(image) }
    func deleteImage(_ id: UUID) async throws(LabError) { savedImages.removeAll { $0.id == id } }
    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

final class FilesStub: LabFileLocations {
    final class Box: @unchecked Sendable {
        var value: [String] = []
    }

    let removed = Box()

    func newAdapterDirectory(name: String) -> String { "/adapters/\(name)" }
    func newModelDirectory(name: String) -> String { "/models/\(name)" }
    func newImagePath() -> String { "/images/new.png" }
    func remove(_ path: String) { removed.value.append(path) }
}
