//
//  LabViewModelTests.swift
//  LabFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import LabFeature
import SundeskDomain
import Testing

@MainActor
@Suite("LabViewModel")
struct LabViewModelTests {
    private func makeViewModel(failure: LabError? = nil) -> LabViewModel {
        LabViewModel(lab: LabStub(failure: failure), modelManagement: ModelsStub(), loadVaultTree: TreeStub())
    }

    private func waitUntilIdle(_ viewModel: LabViewModel) async {
        for _ in 0..<200 where viewModel.isRunning {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("手元の LLM とフォルダを読む")
    func loads() async {
        let viewModel = makeViewModel()

        await viewModel.load()

        #expect(viewModel.models.contains("mlx-community/gemma-3-1b-it-4bit"))
        #expect(!viewModel.models.contains("cl-nagoya/ruri-v3-130m"))
        #expect(viewModel.folders == ["数学"])
    }

    @Test("トークン、次のトークン、Attention を計算して、見やすい形にする")
    func inspects() async {
        let viewModel = makeViewModel()

        viewModel.section = .tokens
        viewModel.run()
        await waitUntilIdle(viewModel)
        #expect(viewModel.tokens.map(\.text) == ["富士", "山␣は"])

        viewModel.section = .nextToken
        viewModel.run()
        await waitUntilIdle(viewModel)
        #expect(viewModel.distribution.map(\.text) == ["日本"])
        #expect(viewModel.entropy == 1.2)

        viewModel.section = .attention
        viewModel.attentionHead = 5
        viewModel.run()
        await waitUntilIdle(viewModel)
        #expect(viewModel.attention?.matrix(head: nil) == [[1, 0], [0.5, 0.5]])
        #expect(viewModel.attentionHead == nil)
    }

    @Test("生成したトークンを確率ごとに並べる")
    func generates() async {
        let viewModel = makeViewModel()
        viewModel.section = .generate

        viewModel.run()
        await waitUntilIdle(viewModel)

        #expect(viewModel.generated.map(\.rawText) == ["日本", "一"])
        #expect(viewModel.tokensPerSecond == 30)
    }

    @Test("失敗したらメッセージを出す")
    func failure() async {
        let viewModel = makeViewModel(failure: .engine("このモデルの構造には対応していません"))
        viewModel.section = .logitLens

        viewModel.run()
        await waitUntilIdle(viewModel)

        #expect(viewModel.errorMessage == "このモデルの構造には対応していません")
        #expect(!viewModel.isRunning)
    }

    @Test("steering は正と負の文がないと始めない")
    func steeringNeedsSentences() async {
        let viewModel = makeViewModel()
        viewModel.section = .steering
        viewModel.steeringNegative = "  "

        viewModel.run()
        await waitUntilIdle(viewModel)

        #expect(viewModel.errorMessage == "正と負の文を、それぞれ 1 つ以上入れてください")
    }
}

private struct LabStub: LabUseCases {
    let failure: LabError?

    func callAsFunction(_ prompt: LabPrompt) async throws(LabError) -> [TokenPiece] {
        [TokenPiece(id: 1, text: "富士", start: 0, end: 2), TokenPiece(id: 2, text: "山 は", start: 2, end: 5)]
    }

    func callAsFunction(_ prompt: LabPrompt, topK: Int, temperature: Double) async throws(LabError)
        -> NextTokenDistribution
    {
        NextTokenDistribution(tokens: [TokenProbability(id: 3, text: "日本", probability: 0.6)], entropy: 1.2)
    }

    func callAsFunction(
        _ prompt: LabPrompt, settings: SamplingSettings, adapter: Adapter?
    ) -> AsyncThrowingStream<LabGenerationEvent, any Error> {
        AsyncThrowingStream { continuation in
            for text in ["日本", "一"] {
                continuation.yield(
                    .token(
                        GeneratedToken(token: TokenProbability(id: 0, text: text, probability: 0.4), alternatives: [])))
            }
            continuation.yield(.done(tokensPerSecond: 30))
            continuation.finish()
        }
    }

    func callAsFunction(_ prompt: LabPrompt, layer: Int) async throws(LabError) -> AttentionMap {
        AttentionMap(
            tokens: ["a", "b"], layerCount: 4, headCount: 2, layer: layer, heads: [], mean: [[1, 0], [0.5, 0.5]])
    }

    func callAsFunction(_ prompt: LabPrompt, topK: Int) async throws(LabError) -> LogitLens {
        if let failure { throw failure }
        return LogitLens(tokens: [], layers: [])
    }

    func callAsFunction(activationsOf prompt: LabPrompt) async throws(LabError) -> ActivationNorms {
        ActivationNorms(tokens: [], norms: [])
    }

    func callAsFunction(
        model: String, folder: String, name: String, settings: LoRASettings
    ) -> AsyncThrowingStream<LoRAEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func callAsFunction(
        _ prompt: LabPrompt, steering: SteeringSetup, settings: SamplingSettings
    ) async throws(LabError) -> (vector: SteeringVector, comparison: SteeringComparison) {
        (
            SteeringVector(model: "m", layer: steering.layer, values: [], norm: 1),
            SteeringComparison(baseline: "a", steered: "b")
        )
    }

    func experiments() async throws(LabError) -> [Experiment] { [] }
    func deleteExperiment(_ id: UUID) async throws(LabError) {}
    func adapters() async throws(LabError) -> [Adapter] { [] }
    func deleteAdapter(_ adapter: Adapter) async throws(LabError) {}
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private struct ModelsStub: ModelManagementUseCase {
    func localModels() async throws(LabError) -> [LocalModel] {
        [
            LocalModel(id: "mlx-community/gemma-3-1b-it-4bit", kind: .llm, sizeBytes: 1, path: "/a"),
            LocalModel(id: "cl-nagoya/ruri-v3-130m", kind: .embedding, sizeBytes: 1, path: "/b"),
        ]
    }

    func download(_ id: String) -> AsyncThrowingStream<DownloadEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(downloaded: 50, total: 100))
            continuation.yield(.done(path: "/x"))
            continuation.finish()
        }
    }

    func delete(_ id: String) async throws(LabError) {}
    func loadedModels() async throws(LabError) -> LoadedModels { .none }
    func unload(_ kind: ModelKind?) async throws(LabError) {}
}

private struct TreeStub: LoadVaultTreeUseCase {
    func callAsFunction() async throws(VaultError) -> VaultNode {
        VaultNode(
            id: "", name: "Vault", kind: .folder,
            children: [
                VaultNode(id: "数学", name: "数学", kind: .folder, children: []),
                VaultNode(id: "ホーム.md", name: "ホーム.md", kind: .markdown),
            ])
    }
}

@MainActor
@Suite("ModelsViewModel")
struct ModelsViewModelTests {
    @Test("手元のモデルを種類と大きさつきで出し、取り込み終えたら読み直す")
    func loadsAndDownloads() async {
        let viewModel = ModelsViewModel(management: ModelsStub())
        await viewModel.load()
        #expect(viewModel.models.map(\.kind) == ["LLM", "埋め込み"])

        viewModel.startDownload("mlx-community/Qwen3-0.6B-4bit")
        #expect(viewModel.download?.id == "mlx-community/Qwen3-0.6B-4bit")
        for _ in 0..<200 where viewModel.download != nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.download == nil)
        #expect(viewModel.errorMessage == nil)
    }
}
