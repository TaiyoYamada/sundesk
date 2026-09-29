//
//  LabRepositories.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// モデルの管理（エンジンの Hugging Face のキャッシュ）。
public protocol ModelRepository: Sendable {
    func localModels() async throws(LabError) -> [LocalModel]
    func download(_ id: String) -> AsyncThrowingStream<DownloadEvent, any Error>
    func delete(_ id: String) async throws(LabError)
    func loadedModels() async throws(LabError) -> LoadedModels
    func unload(_ kind: ModelKind?) async throws(LabError)
}

/// LLM の中を覗く・いじる計算（エンジン）。
public protocol LabEngine: Sendable {
    func tokenize(_ prompt: LabPrompt) async throws(LabError) -> [TokenPiece]
    func nextToken(_ prompt: LabPrompt, topK: Int, temperature: Double) async throws(LabError) -> NextTokenDistribution
    func generate(
        _ prompt: LabPrompt, settings: SamplingSettings, alternatives: Int, adapter: String?
    ) -> AsyncThrowingStream<LabGenerationEvent, any Error>
    func attention(_ prompt: LabPrompt, layer: Int) async throws(LabError) -> AttentionMap
    func logitLens(_ prompt: LabPrompt, topK: Int) async throws(LabError) -> LogitLens
    func activations(_ prompt: LabPrompt) async throws(LabError) -> ActivationNorms
    func trainLoRA(
        model: String, texts: [String], adapterPath: String, settings: LoRASettings
    ) -> AsyncThrowingStream<LoRAEvent, any Error>
    func steeringVector(
        model: String, layer: Int, positive: [String], negative: [String]
    ) async throws(LabError) -> SteeringVector
    func steer(
        _ prompt: LabPrompt, vector: SteeringVector, strength: Double, settings: SamplingSettings
    ) async throws(LabError) -> SteeringComparison
}

/// 画像生成（エンジン）。
public protocol ImageEngine: Sendable {
    func imageModels() async throws(LabError) -> [ImageModelOption]
    func generate(_ request: ImageRequest, outputPath: String) -> AsyncThrowingStream<ImageGenerationEvent, any Error>
}

/// 実験、アダプタ、生成した画像の記録（アプリ全体で 1 つ）。
public protocol LabRecordRepository: Sendable {
    func experiments() async throws(LabError) -> [Experiment]
    func save(_ experiment: Experiment) async throws(LabError)
    func deleteExperiment(_ id: UUID) async throws(LabError)

    func adapters() async throws(LabError) -> [Adapter]
    func save(_ adapter: Adapter) async throws(LabError)
    func deleteAdapter(_ id: UUID) async throws(LabError)

    func images() async throws(LabError) -> [GeneratedImage]
    func save(_ image: GeneratedImage) async throws(LabError)
    func deleteImage(_ id: UUID) async throws(LabError)

    func changes() -> AsyncStream<Void>
}

/// 大きなファイル（アダプタ、画像）の置き場所。
public protocol LabFileLocations: Sendable {
    /// 新しいアダプタのフォルダ。
    func newAdapterDirectory(name: String) -> String
    /// 新しい画像のファイル。
    func newImagePath() -> String
    /// ファイルやフォルダを消す。
    func remove(_ path: String)
}
