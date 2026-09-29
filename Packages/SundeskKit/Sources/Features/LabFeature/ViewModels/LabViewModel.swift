//
//  LabViewModel.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// LLM の実験室。プロンプトを入れて、トークン、確率、Attention、層ごとの予測や活性を覗き、LoRA や steering でいじる。
@MainActor
@Observable
public final class LabViewModel {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case tokens, nextToken, generate, attention, logitLens, activations, lora, steering, records

        public var id: Self { self }

        public var title: String {
            switch self {
            case .tokens: "トークン"
            case .nextToken: "次のトークン"
            case .generate: "生成"
            case .attention: "Attention"
            case .logitLens: "Logit lens"
            case .activations: "活性"
            case .lora: "LoRA"
            case .steering: "Steering"
            case .records: "記録"
            }
        }

        public var systemImage: String {
            switch self {
            case .tokens: "textformat.characters.dottedunderline"
            case .nextToken: "chart.bar.xaxis"
            case .generate: "text.cursor"
            case .attention: "square.grid.3x3.fill"
            case .logitLens: "square.stack.3d.up"
            case .activations: "waveform.path.ecg"
            case .lora: "slider.horizontal.below.square.and.square.filled"
            case .steering: "arrow.triangle.turn.up.right.diamond"
            case .records: "clock.arrow.circlepath"
            }
        }

        /// プロンプトを使う画面か。
        public var usesPrompt: Bool { ![.lora, .records].contains(self) }
    }

    public var section: Section = .tokens
    public private(set) var models: [String] = LabViewModel.suggestedModels
    public var model = LabViewModel.suggestedModels[0]
    public var prompt = "東京は日本の首都です。富士山は"
    public var chatTemplate = false
    // 生成の設定
    public var temperature = 0.7
    public var topP = 0.95
    public var maxTokens = 200
    /// nil なら毎回変える。
    public var seed: Int?
    public private(set) var isRunning = false
    public private(set) var status: String?
    public var errorMessage: String?

    // 結果
    public private(set) var tokens: [TokenItem] = []
    public private(set) var distribution: [ProbabilityItem] = []
    public private(set) var entropy: Double?
    public var nextTokenTemperature = 1.0
    public private(set) var generated: [GeneratedTokenItem] = []
    public var selectedGeneratedIndex: Int?
    public private(set) var tokensPerSecond: Double?
    public private(set) var attention: AttentionItem?
    public var attentionLayer = 0
    public var attentionHead: Int?
    public private(set) var lens: LogitLensItem?
    public private(set) var activations: ActivationsItem?

    // いじる
    public private(set) var folders: [String] = []
    public var loraFolder = ""
    public var loraName = "ノートの文体"
    public var loraIterations = 200
    public var loraRank = 8
    public var loraLayers = 8
    public var loraLearningRate = 1e-5
    public static let learningRates = [1e-5, 2e-5, 5e-5, 1e-4, 2e-4]
    public private(set) var trainingLoss: [LossPoint] = []
    public private(set) var validationLoss: [LossPoint] = []
    public private(set) var trainingProgress: Double?
    public private(set) var adapters: [AdapterItem] = []
    public var selectedAdapterID: UUID?
    public var steeringLayer = 8
    public var steeringPositive = "嬉しい\n楽しい\n最高の気分だ"
    public var steeringNegative = "悲しい\nつらい\n最悪の気分だ"
    public var steeringStrength = 4.0
    public private(set) var steering: SteeringItem?
    public private(set) var experiments: [ExperimentItem] = []

    /// 実験室でまず試す、小さなモデル。
    public static let suggestedModels = [
        "mlx-community/Qwen3-0.6B-4bit", "mlx-community/Qwen3-1.7B-4bit", ChatModelOption.defaultMLXID,
    ]

    @ObservationIgnored private let lab: any LabUseCases
    @ObservationIgnored private let modelManagement: any ModelManagementUseCase
    @ObservationIgnored private let loadVaultTree: any LoadVaultTreeUseCase
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var adapterModels: [UUID: Adapter] = [:]

    public init(
        lab: any LabUseCases, modelManagement: any ModelManagementUseCase, loadVaultTree: any LoadVaultTreeUseCase
    ) {
        self.lab = lab
        self.modelManagement = modelManagement
        self.loadVaultTree = loadVaultTree
    }

    // MARK: - 読み込み

    public func load() async {
        if let local = try? await modelManagement.localModels() {
            let llms = local.filter { $0.kind == .llm }.map(\.id)
            models = Self.suggestedModels + llms.filter { !Self.suggestedModels.contains($0) }
        }
        if let tree = try? await loadVaultTree() {
            folders = tree.children?.filter(\.isFolder).map(\.path).sorted() ?? []
        }
        await reloadRecords()
    }

    public func observeRecords() async {
        for await _ in lab.changes() {
            await reloadRecords()
        }
    }

    private func reloadRecords() async {
        experiments = ((try? await lab.experiments()) ?? []).map(ExperimentItem.init)
        let loaded = (try? await lab.adapters()) ?? []
        adapterModels = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        adapters = loaded.map(AdapterItem.init)
        if let selectedAdapterID, adapterModels[selectedAdapterID] == nil { self.selectedAdapterID = nil }
    }

    /// 選んでいるモデルに合う LoRA。
    public var adaptersForModel: [AdapterItem] {
        adapters.filter { $0.model == model }
    }

    private var sampling: SamplingSettings {
        SamplingSettings(temperature: temperature, topP: topP, maxTokens: maxTokens, seed: seed)
    }

    private var loraSettings: LoRASettings {
        LoRASettings(
            iterations: loraIterations, rank: loraRank, learningRate: loraLearningRate, layerCount: loraLayers)
    }

    // MARK: - 実行

    /// 今の画面の計算を実行する。
    public func run() {
        guard !isRunning else { return }
        let prompt = LabPrompt(model: model, text: prompt, chatTemplate: chatTemplate)
        switch section {
        case .tokens: perform { self.tokens = try await self.lab(prompt).enumerated().map(TokenItem.init) }
        case .nextToken: perform { try await self.predictNextToken(prompt) }
        case .generate: startGeneration(prompt)
        case .attention: perform { try await self.inspectAttention(prompt) }
        case .logitLens: perform { self.lens = LogitLensItem(try await self.lab(prompt, topK: 3)) }
        case .activations: perform { self.activations = ActivationsItem(try await self.lab(activationsOf: prompt)) }
        case .lora: startTraining()
        case .steering: perform { try await self.steer(prompt) }
        case .records: break
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        status = nil
    }

    private func perform(_ body: @escaping @MainActor () async throws -> Void) {
        isRunning = true
        errorMessage = nil
        status = "計算しています（初めてのモデルは、読み込みとダウンロードに時間がかかります）"
        task = Task {
            do {
                try await body()
            } catch is CancellationError {
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
            status = nil
            task = nil
        }
    }

    private func predictNextToken(_ prompt: LabPrompt) async throws {
        let result = try await lab(prompt, topK: 20, temperature: nextTokenTemperature)
        distribution = result.tokens.map(ProbabilityItem.init)
        entropy = result.entropy
    }

    private func inspectAttention(_ prompt: LabPrompt) async throws {
        let map = try await lab(prompt, layer: attentionLayer)
        attention = AttentionItem(map)
        attentionLayer = min(attentionLayer, max(map.layerCount - 1, 0))
        if let head = attentionHead, head >= map.headCount { attentionHead = nil }
    }

    /// 層を変えて、Attention を計算し直す。
    public func showAttention(layer: Int) {
        attentionLayer = layer
        if section == .attention, attention != nil { run() }
    }

    private func startGeneration(_ prompt: LabPrompt) {
        generated = []
        selectedGeneratedIndex = nil
        tokensPerSecond = nil
        let adapter = selectedAdapterID.flatMap { adapterModels[$0] }
        let stream = lab(prompt, settings: sampling, adapter: adapter)
        perform {
            for try await event in stream {
                switch event {
                case .loading:
                    self.status = "モデルを読み込んでいます"
                case .token(let token):
                    self.status = nil
                    self.generated.append(GeneratedTokenItem(index: self.generated.count, token))
                case .done(let speed):
                    self.tokensPerSecond = speed
                }
            }
        }
    }

    private func startTraining() {
        trainingLoss = []
        validationLoss = []
        trainingProgress = 0
        let stream = lab(model: model, folder: loraFolder, name: loraName, settings: loraSettings)
        perform {
            for try await event in stream {
                switch event {
                case .loading:
                    self.status = "モデルを読み込んでいます"
                case .progress(let iteration, let total, let loss):
                    self.status = "学習しています（\(iteration)/\(total)）"
                    self.trainingProgress = total > 0 ? Double(iteration) / Double(total) : nil
                    self.trainingLoss.append(LossPoint(iteration: iteration, loss: loss))
                case .validation(let iteration, let loss):
                    self.validationLoss.append(LossPoint(iteration: iteration, loss: loss))
                case .done:
                    self.trainingProgress = 1
                }
            }
        }
    }

    private func steer(_ prompt: LabPrompt) async throws {
        let lines: (String) -> [String] = {
            $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let positive = lines(steeringPositive)
        let negative = lines(steeringNegative)
        guard !positive.isEmpty, !negative.isEmpty else {
            throw LabError.engine("正と負の文を、それぞれ 1 つ以上入れてください")
        }
        let setup = SteeringSetup(
            layer: steeringLayer, positive: positive, negative: negative, strength: steeringStrength)
        let result = try await lab(prompt, steering: setup, settings: sampling)
        steering = SteeringItem(
            baseline: result.comparison.baseline, steered: result.comparison.steered,
            norm: String(format: "%.2f", result.vector.norm))
    }

    // MARK: - 記録

    public func deleteExperiment(_ id: UUID) async {
        try? await lab.deleteExperiment(id)
    }

    public func deleteAdapter(_ id: UUID) async {
        guard let adapter = adapterModels[id] else { return }
        do {
            try await lab.deleteAdapter(adapter)
        } catch {
            errorMessage = error.message
        }
    }
}
