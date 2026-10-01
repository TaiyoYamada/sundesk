//
//  ForgeViewModel.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 工房。モデルを量子化し、変換し、混ぜ、枝を刈り、蒸留して、できたものを比べる。
@MainActor
@Observable
public final class ForgeViewModel {
    // 選べるもの
    public private(set) var models: [ModelChoice] = []
    public private(set) var adapters: [AdapterItem] = []
    public private(set) var folders: [String] = []

    // 量子化
    public var quantizeModel = ""
    public var quantizeMethod: QuantizeMethodChoice = .affine
    public var quantizeBits = 4
    public var quantizeGroupSize = 64
    public var quantizeMixed = ""
    /// 1 行に 1 つ「重みの名前の一部=ビット数」（ビット数が空なら量子化しない）。
    public var quantizeOverrides = ""
    public static let mixedRecipes = ["", "mixed_2_6", "mixed_3_4", "mixed_3_6", "mixed_4_6"]

    // 変換・焼き込み・合成
    public var convertModel = "Qwen/Qwen3-0.6B"
    public var convertDType = "bfloat16"
    public var convertBits: Int?
    public var fuseModel = ""
    public var fuseAdapterID: UUID?
    public var fuseDequantize = false
    public var mergeFirst = ""
    public var mergeSecond = ""
    public var mergeSlerp = true
    public var mergeRatio = 0.5

    // 枝刈り
    public var pruneModel = ""
    /// 取り除く層（「20, 21」のように）。
    public var pruneLayers = ""
    /// 0 にするヘッド（「3.5, 4.1」のように「層.ヘッド」）。
    public var pruneHeads = ""

    // 蒸留
    public var teacher = ChatModelOption.defaultMLXID
    public var student = "mlx-community/Qwen3-0.6B-4bit"
    public var distillFolder = ""
    public var distillIterations = 200
    public var distillTemperature = 2.0
    public var distillAlpha = 0.5
    public var distillLearningRate = 1e-5
    public var distillUsesLoRA = true

    // 比べる
    public var evaluationModels: Set<String> = []
    public var evaluationFolder = ""
    public var evaluationPrompts = "日本で一番高い山は\n固有値とは"
    public private(set) var evaluationResults: [EvaluationItem] = []

    /// 作るものの名前（出力のフォルダ名になる）。
    public var outputName = ""
    public private(set) var isRunning = false
    public private(set) var progress: ForgeProgressItem?
    public private(set) var trainingLoss: [LossPoint] = []
    public private(set) var lastOutput: ForgedItem?
    public var errorMessage: String?

    @ObservationIgnored private let forge: any ForgeUseCases
    @ObservationIgnored private let modelManagement: any ModelManagementUseCase
    @ObservationIgnored private let records: any LabRecordsUseCase
    @ObservationIgnored private let loadVaultTree: any LoadVaultTreeUseCase
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var adapterPaths: [UUID: String] = [:]

    public init(
        forge: any ForgeUseCases, modelManagement: any ModelManagementUseCase, records: any LabRecordsUseCase,
        loadVaultTree: any LoadVaultTreeUseCase
    ) {
        self.forge = forge
        self.modelManagement = modelManagement
        self.records = records
        self.loadVaultTree = loadVaultTree
    }

    // MARK: - 読み込み

    public func load() async {
        if let local = try? await modelManagement.localModels() {
            models = local.filter { $0.kind == .llm }.map(ModelChoice.init)
        }
        for fallback in LabViewModel.suggestedModels where !models.contains(where: { $0.id == fallback }) {
            models.append(ModelChoice(id: fallback, name: fallback, isLocal: false))
        }
        let adapterList = (try? await records.adapters()) ?? []
        adapterPaths = Dictionary(adapterList.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
        adapters = adapterList.map(AdapterItem.init)
        if let tree = try? await loadVaultTree() {
            folders = tree.children?.filter(\.isFolder).map(\.path).sorted() ?? []
        }
        let first = models.first?.id ?? ""
        for keyPath in [\ForgeViewModel.quantizeModel, \.fuseModel, \.mergeFirst, \.mergeSecond, \.pruneModel]
        where self[keyPath: keyPath].isEmpty {
            self[keyPath: keyPath] = first
        }
    }

    // MARK: - 作る

    public func quantize() {
        let method: QuantizationMethod =
            switch quantizeMethod {
            case .affine: .affine(bits: quantizeBits, groupSize: quantizeGroupSize, mixed: quantizeMixed.nilIfEmpty)
            case .simulated: .simulated(bits: quantizeBits)
            case .ternary: .ternary
            }
        let overrides = quantizeOverrides.split(separator: "\n").compactMap { line -> QuantizationOverride? in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let pattern = parts.first, !pattern.isEmpty else { return nil }
            return QuantizationOverride(pattern: pattern, bits: parts.count > 1 ? Int(parts[1]) : nil)
        }
        let suffix =
            switch quantizeMethod {
            case .affine: "\(quantizeBits)bit" + (quantizeMixed.isEmpty ? "" : "-\(quantizeMixed)")
            case .simulated: "sim\(quantizeBits)bit"
            case .ternary: "ternary"
            }
        start(
            .quantize(model: quantizeModel, method: method, overrides: overrides),
            defaultName: base(quantizeModel) + "-" + suffix)
    }

    public func convert() {
        start(
            .convert(model: convertModel, dtype: convertDType, quantizeBits: convertBits),
            defaultName: base(convertModel) + "-mlx")
    }

    public func fuse() {
        guard let fuseAdapterID, let path = adapterPaths[fuseAdapterID] else {
            errorMessage = "焼き込む LoRA を選んでください"
            return
        }
        start(
            .fuse(model: fuseModel, adapterPath: path, dequantize: fuseDequantize),
            defaultName: base(fuseModel) + "-fused")
    }

    public func merge() {
        start(
            .merge(first: mergeFirst, second: mergeSecond, method: mergeSlerp ? .slerp : .linear, ratio: mergeRatio),
            defaultName: "merge-\(base(mergeFirst))-\(base(mergeSecond))")
    }

    public func prune() {
        let layers = pruneLayers.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }
        let heads = pruneHeads.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { item -> AttentionHead? in
            let parts = item.split(separator: ".").compactMap { Int($0) }
            return parts.count == 2 ? AttentionHead(layer: parts[0], head: parts[1]) : nil
        }
        guard !layers.isEmpty || !heads.isEmpty else {
            errorMessage = "取り除く層かヘッドを入れてください"
            return
        }
        start(
            .prune(model: pruneModel, dropLayers: layers, dropHeads: heads), defaultName: base(pruneModel) + "-pruned")
    }

    public func distill() {
        let settings = DistillationSettings(
            iterations: distillIterations, learningRate: distillLearningRate, temperature: distillTemperature,
            alpha: distillAlpha, loraRank: distillUsesLoRA ? 8 : nil)
        start(
            .distill(teacher: teacher, student: student, folder: distillFolder, settings: settings),
            defaultName: base(student) + "-distilled")
    }

    private func start(_ job: ForgeJob, defaultName: String) {
        guard !isRunning else { return }
        let name = outputName.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? defaultName
        errorMessage = nil
        trainingLoss = []
        lastOutput = nil
        progress = ForgeProgressItem(title: "準備しています", fraction: nil)
        isRunning = true
        let stream = forge(job, name: name)
        task = Task {
            do {
                for try await event in stream {
                    apply(event)
                }
            } catch is CancellationError {
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
            progress = nil
            task = nil
            outputName = ""
            await load()
        }
    }

    private func apply(_ event: ForgeEvent) {
        switch event {
        case .loading(let model):
            progress = ForgeProgressItem(title: "読み込んでいます（\(base(model))）", fraction: nil)
        case .progress(let stage, let fraction, let message):
            progress = ForgeProgressItem(
                title: Self.stageTitle(stage) + (message.map { "（\($0)）" } ?? ""), fraction: fraction)
        case .training(let iteration, let total, let loss, _, _):
            progress = ForgeProgressItem(
                title: "学習しています（\(iteration)/\(total)）", fraction: total > 0 ? Double(iteration) / Double(total) : nil)
            trainingLoss.append(LossPoint(iteration: iteration, loss: loss))
        case .validation:
            break
        case .done(let forged):
            lastOutput = ForgedItem(forged)
        }
    }

    public func cancel() {
        task?.cancel()
    }

    // MARK: - 比べる

    public func evaluate() {
        guard !isRunning else { return }
        let targets = evaluationModels.sorted().map { EvaluationTarget(model: $0) }
        guard !targets.isEmpty else {
            errorMessage = "比べるモデルを選んでください"
            return
        }
        let prompts = evaluationPrompts.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        errorMessage = nil
        evaluationResults = []
        isRunning = true
        progress = ForgeProgressItem(title: "準備しています", fraction: 0)
        let stream = forge(targets, folder: evaluationFolder, prompts: prompts, maxTokens: 48)
        task = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .loading(let model):
                        progress = ForgeProgressItem(
                            title: "測っています（\(base(model))）",
                            fraction: Double(evaluationResults.count) / Double(targets.count))
                    case .result(let result):
                        evaluationResults.append(EvaluationItem(result))
                    }
                }
            } catch is CancellationError {
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
            progress = nil
            task = nil
        }
    }

    /// 手元に作ったモデルを消す。
    public func deleteLocalModel(_ id: String) async {
        guard let model = models.first(where: { $0.id == id }), model.isLocal else { return }
        forge(deleting: id)
        await load()
    }

    // MARK: - 補助

    private func base(_ model: String) -> String {
        (model.split(separator: "/").last.map(String.init) ?? model).replacing(/-(4|8)bit$/, with: "")
    }

    static func stageTitle(_ stage: String) -> String {
        switch stage {
        case "loading": "読み込んでいます"
        case "converting": "変換しています"
        case "quantizing": "量子化しています"
        case "merging": "混ぜています"
        case "pruning": "枝を刈っています"
        case "fusing": "焼き込んでいます"
        case "saving": "保存しています"
        default: stage
        }
    }
}

// MARK: - 表示用の型

public enum QuantizeMethodChoice: String, CaseIterable, Identifiable, Sendable {
    case affine, simulated, ternary

    public var id: Self { self }

    public var title: String {
        switch self {
        case .affine: "本物の量子化（MLX）"
        case .simulated: "真似る（好きなビット数）"
        case .ternary: "3 値（1.58 ビット）"
        }
    }
}

public struct ModelChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// 工房で作ったモデル（アプリのフォルダにある）。
    public let isLocal: Bool

    init(id: String, name: String, isLocal: Bool) {
        self.id = id
        self.name = name
        self.isLocal = isLocal
    }

    init(_ model: LocalModel) {
        id = model.id
        isLocal = model.id.hasPrefix("/")
        name = isLocal ? "🛠 " + (model.id as NSString).lastPathComponent : model.id
    }
}

public struct ForgeProgressItem: Hashable, Sendable {
    public let title: String
    public let fraction: Double?
}

public struct ForgedItem: Hashable, Sendable {
    public let name: String
    public let path: String
    public let detail: String

    init(_ model: ForgedModel) {
        name = model.name
        path = model.path
        let size = model.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let bits = model.bitsPerWeight.map { String(format: "%.2f ビット/重み", $0) }
        detail = ([model.kind == .adapter ? "LoRA" : "モデル"] + [size, bits].compactMap { $0 }).joined(separator: "・")
    }
}

public struct EvaluationItem: Identifiable, Hashable, Sendable {
    public var id: String { model + (adapter ?? "") }
    public let model: String
    public let adapter: String?
    public let perplexity: Double
    public let perplexityText: String
    public let speed: String
    public let size: String
    public let memory: String
    public let samples: [String]

    init(_ result: EvaluationResult) {
        model =
            result.target.model.hasPrefix("/")
            ? "🛠 " + (result.target.model as NSString).lastPathComponent : result.target.model
        adapter = result.target.adapter.map { ($0 as NSString).lastPathComponent }
        perplexity = result.perplexity
        perplexityText = String(format: "%.2f", result.perplexity)
        speed = String(format: "%.0f トークン/秒", result.tokensPerSecond)
        size = result.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        memory = result.peakMemoryBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "—"
        samples = result.samples
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
