//
//  LabModels.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - モデルの管理

public enum ModelKind: String, Codable, Sendable {
    case llm
    case embedding
    case image
    case other
}

/// 手元にあるモデル（Hugging Face のキャッシュ）。
public struct LocalModel: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: ModelKind
    public let sizeBytes: Int64
    public let path: String

    public init(id: String, kind: ModelKind, sizeBytes: Int64, path: String) {
        self.id = id
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.path = path
    }
}

/// 今メモリに載っているモデル。
public struct LoadedModels: Hashable, Sendable {
    public let llm: String?
    public let image: String?
    public let embedding: String?
    public let adapter: String?

    public init(llm: String?, image: String?, embedding: String?, adapter: String?) {
        self.llm = llm
        self.image = image
        self.embedding = embedding
        self.adapter = adapter
    }

    public static let none = LoadedModels(llm: nil, image: nil, embedding: nil, adapter: nil)
}

public enum DownloadEvent: Hashable, Sendable {
    case progress(downloaded: Int64, total: Int64?)
    case done(path: String)
}

// MARK: - 覗く

/// トークンの区切り。
public struct TokenPiece: Hashable, Sendable {
    public let id: Int
    public let text: String
    /// 元の文字列での位置（Unicode のコードポイント）。分からなければ nil。
    public let start: Int?
    public let end: Int?

    public init(id: Int, text: String, start: Int?, end: Int?) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
    }
}

/// トークンと、その確率。
public struct TokenProbability: Hashable, Sendable {
    public let id: Int
    public let text: String
    public let probability: Double

    public init(id: Int, text: String, probability: Double) {
        self.id = id
        self.text = text
        self.probability = probability
    }
}

/// 次のトークンの確率分布（上位）。
public struct NextTokenDistribution: Hashable, Sendable {
    public let tokens: [TokenProbability]
    /// 分布全体のエントロピー（ビットではなく自然対数）。
    public let entropy: Double

    public init(tokens: [TokenProbability], entropy: Double) {
        self.tokens = tokens
        self.entropy = entropy
    }
}

public struct SamplingSettings: Hashable, Sendable, Codable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var maxTokens: Int
    public var seed: Int?

    public init(temperature: Double = 0.7, topP: Double = 0.95, topK: Int = 0, maxTokens: Int = 200, seed: Int? = nil) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.seed = seed
    }
}

/// 生成した 1 トークンと、他の候補。
public struct GeneratedToken: Hashable, Sendable {
    public let token: TokenProbability
    public let alternatives: [TokenProbability]

    public init(token: TokenProbability, alternatives: [TokenProbability]) {
        self.token = token
        self.alternatives = alternatives
    }
}

public enum LabGenerationEvent: Hashable, Sendable {
    case loading
    case token(GeneratedToken)
    case done(tokensPerSecond: Double?)
}

/// ある層の Attention。`heads[h][i][j]` は i 番目のトークンが j 番目を見る重み。
public struct AttentionMap: Hashable, Sendable {
    public let tokens: [String]
    public let layerCount: Int
    public let headCount: Int
    public let layer: Int
    public let heads: [[[Double]]]
    public let mean: [[Double]]

    public init(tokens: [String], layerCount: Int, headCount: Int, layer: Int, heads: [[[Double]]], mean: [[Double]]) {
        self.tokens = tokens
        self.layerCount = layerCount
        self.headCount = headCount
        self.layer = layer
        self.heads = heads
        self.mean = mean
    }
}

/// logit lens。各層の途中の状態から予測したトークン。`layers[l][p]` は層 l・位置 p の上位の予測。
public struct LogitLens: Hashable, Sendable {
    public let tokens: [String]
    public let layers: [[[TokenProbability]]]

    public init(tokens: [String], layers: [[[TokenProbability]]]) {
        self.tokens = tokens
        self.layers = layers
    }
}

/// 残差ストリームの大きさ。`norms[l][p]` は層 l・位置 p の L2 ノルム。
public struct ActivationNorms: Hashable, Sendable {
    public let tokens: [String]
    public let norms: [[Double]]

    public init(tokens: [String], norms: [[Double]]) {
        self.tokens = tokens
        self.norms = norms
    }
}

/// 覗くときの入力。
public struct LabPrompt: Hashable, Sendable, Codable {
    public let model: String
    public let text: String
    /// チャットの形に包むか（指示モデルに質問するとき）。
    public let chatTemplate: Bool

    public init(model: String, text: String, chatTemplate: Bool) {
        self.model = model
        self.text = text
        self.chatTemplate = chatTemplate
    }
}

// MARK: - いじる

public struct LoRASettings: Hashable, Sendable, Codable {
    public var iterations: Int
    public var rank: Int
    public var learningRate: Double
    public var batchSize: Int
    public var maxSequenceLength: Int
    public var layerCount: Int

    public init(
        iterations: Int = 200, rank: Int = 8, learningRate: Double = 1e-5, batchSize: Int = 1,
        maxSequenceLength: Int = 1024, layerCount: Int = 8
    ) {
        self.iterations = iterations
        self.rank = rank
        self.learningRate = learningRate
        self.batchSize = batchSize
        self.maxSequenceLength = maxSequenceLength
        self.layerCount = layerCount
    }
}

public enum LoRAEvent: Hashable, Sendable {
    case loading
    case progress(iteration: Int, total: Int, trainLoss: Double)
    case validation(iteration: Int, loss: Double)
    case done(adapterPath: String)
}

/// 学習した LoRA のアダプタ。
public struct Adapter: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let model: String
    public let path: String
    public let settings: LoRASettings
    /// 学習に使ったノート（説明）。
    public let source: String
    public let finalLoss: Double?
    public let createdAt: Date

    public init(
        id: UUID, name: String, model: String, path: String, settings: LoRASettings, source: String, finalLoss: Double?,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.path = path
        self.settings = settings
        self.source = source
        self.finalLoss = finalLoss
        self.createdAt = createdAt
    }
}

/// steering のベクトル（ある層の、2 組の文の平均の差）。
public struct SteeringVector: Hashable, Sendable {
    public let model: String
    public let layer: Int
    public let values: [Float]
    public let norm: Double

    public init(model: String, layer: Int, values: [Float], norm: Double) {
        self.model = model
        self.layer = layer
        self.values = values
        self.norm = norm
    }
}

/// steering の設定。`positive` の文の方へ、`negative` の文から遠ざける。
public struct SteeringSetup: Hashable, Sendable {
    public var layer: Int
    public var positive: [String]
    public var negative: [String]
    /// 足す強さ（負なら逆向き）。
    public var strength: Double

    public init(layer: Int, positive: [String], negative: [String], strength: Double) {
        self.layer = layer
        self.positive = positive
        self.negative = negative
        self.strength = strength
    }
}

public struct SteeringComparison: Hashable, Sendable {
    public let baseline: String
    public let steered: String

    public init(baseline: String, steered: String) {
        self.baseline = baseline
        self.steered = steered
    }
}

// MARK: - 記録

/// 実験の記録（軽い情報だけを毎回残す）。
public struct Experiment: Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case tokenize
        case nextToken
        case generate
        case attention
        case logitLens
        case activations
        case lora
        case steering
        /// 量子化、変換、焼き込み、合成、枝刈り、蒸留。
        case forge
        case evaluate
        case script
    }

    public let id: UUID
    public let kind: Kind
    public let model: String
    public let prompt: String
    /// 設定（人が読める形の「名前: 値」）。
    public let parameters: [String: String]
    /// 結果の要約。
    public let summary: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(), kind: Kind, model: String, prompt: String, parameters: [String: String], summary: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.model = model
        self.prompt = prompt
        self.parameters = parameters
        self.summary = summary
        self.createdAt = createdAt
    }
}

public enum LabError: Error, Equatable, Sendable {
    /// エンジンが動いていない、またはエンジンが失敗を返した。
    case engine(String)
    case storage(String)

    public var message: String {
        switch self {
        case .engine(let message): message
        case .storage(let message): "記録を保存できませんでした: \(message)"
        }
    }
}
