//
//  ForgeModels.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - 作る

/// 量子化のやり方。
public enum QuantizationMethod: Hashable, Sendable {
    /// MLX の本物の量子化（2、3、4、5、6、8 ビット）。`mixed` は層ごとにビット数を変える決まった配分。
    case affine(bits: Int, groupSize: Int, mixed: String?)
    /// 量子化してすぐ戻し、ふつうの数で保存する（1〜8 ビット。本物にないビット数も試せる）。
    case simulated(bits: Int)
    /// −1、0、+1 の 3 値（1.58 ビット）を真似る。
    case ternary
}

/// 重みの名前ごとのビット数の上書き。`bits` が nil ならその重みは量子化しない。
public struct QuantizationOverride: Hashable, Sendable {
    public let pattern: String
    public let bits: Int?

    public init(pattern: String, bits: Int?) {
        self.pattern = pattern
        self.bits = bits
    }
}

public enum MergeMethod: String, Hashable, Sendable {
    case linear
    case slerp
}

/// 取り除くヘッド。
public struct AttentionHead: Hashable, Sendable {
    public let layer: Int
    public let head: Int

    public init(layer: Int, head: Int) {
        self.layer = layer
        self.head = head
    }
}

public struct DistillationSettings: Hashable, Sendable {
    public var iterations: Int
    public var learningRate: Double
    public var temperature: Double
    /// 先生の分布に合わせる損失の割合（残りは正解のトークンの交差エントロピー）。
    public var alpha: Double
    public var maxSequenceLength: Int
    /// 生徒に LoRA を付けて学習するときのランク。nil なら生徒の全体を学習する。
    public var loraRank: Int?

    public init(
        iterations: Int = 200, learningRate: Double = 1e-5, temperature: Double = 2, alpha: Double = 0.5,
        maxSequenceLength: Int = 512, loraRank: Int? = 8
    ) {
        self.iterations = iterations
        self.learningRate = learningRate
        self.temperature = temperature
        self.alpha = alpha
        self.maxSequenceLength = maxSequenceLength
        self.loraRank = loraRank
    }
}

/// モデルを作る仕事。
public enum ForgeJob: Hashable, Sendable {
    case quantize(model: String, method: QuantizationMethod, overrides: [QuantizationOverride])
    /// Hugging Face の PyTorch などのモデルを MLX に変換する（`quantizeBits` が nil なら量子化しない）。
    case convert(model: String, dtype: String, quantizeBits: Int?)
    /// LoRA を本体に焼き込む。
    case fuse(model: String, adapterPath: String, dequantize: Bool)
    case merge(first: String, second: String, method: MergeMethod, ratio: Double)
    case prune(model: String, dropLayers: [Int], dropHeads: [AttentionHead])
    /// Vault の `folder` の下のノートで、先生の分布を生徒に学ばせる。
    case distill(teacher: String, student: String, folder: String, settings: DistillationSettings)

    /// 記録に出す名前。
    public var title: String {
        switch self {
        case .quantize: "量子化"
        case .convert: "変換"
        case .fuse: "焼き込み"
        case .merge: "合成"
        case .prune: "枝刈り"
        case .distill: "蒸留"
        }
    }
}

public enum ForgeEvent: Hashable, Sendable {
    case loading(model: String)
    case progress(stage: String, fraction: Double?, message: String?)
    case training(iteration: Int, total: Int, loss: Double, divergence: Double?, crossEntropy: Double?)
    case validation(iteration: Int, loss: Double)
    case done(ForgedModel)
}

/// 作ったモデル（またはアダプタ）。
public struct ForgedModel: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case model
        case adapter
    }

    public let name: String
    public let path: String
    public let kind: Kind
    public let sizeBytes: Int64?
    public let bitsPerWeight: Double?

    public init(name: String, path: String, kind: Kind, sizeBytes: Int64?, bitsPerWeight: Double?) {
        self.name = name
        self.path = path
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.bitsPerWeight = bitsPerWeight
    }
}

// MARK: - 比べる

/// 比べるモデル（アダプタを付けてもよい）。
public struct EvaluationTarget: Hashable, Sendable {
    public let model: String
    public let adapter: String?

    public init(model: String, adapter: String? = nil) {
        self.model = model
        self.adapter = adapter
    }
}

public struct EvaluationResult: Hashable, Sendable {
    public let target: EvaluationTarget
    public let perplexity: Double
    public let tokens: Int
    public let seconds: Double
    public let tokensPerSecond: Double
    public let sizeBytes: Int64?
    public let peakMemoryBytes: Int64?
    public let samples: [String]

    public init(
        target: EvaluationTarget, perplexity: Double, tokens: Int, seconds: Double, tokensPerSecond: Double,
        sizeBytes: Int64?, peakMemoryBytes: Int64?, samples: [String]
    ) {
        self.target = target
        self.perplexity = perplexity
        self.tokens = tokens
        self.seconds = seconds
        self.tokensPerSecond = tokensPerSecond
        self.sizeBytes = sizeBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.samples = samples
    }
}

public enum EvaluationEvent: Hashable, Sendable {
    case loading(model: String)
    case result(EvaluationResult)
}

// MARK: - 書く

/// スクラッチ（エンジンの中の Python）の出力。
public enum ScratchOutput: Hashable, Sendable {
    case stdout(String)
    case stderr(String)
    /// PNG の画像。
    case image(Data)
    case table(columns: [String], rows: [[String]])
    /// 最後の式の値。
    case value(String)
    case done(seconds: Double)
    case error(message: String, traceback: String?)
}

/// 保存したスクリプト。
public struct Script: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let code: String

    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }
}

/// 最初から用意しておくスクリプト（書き方の例）。
public enum ScriptTemplates {
    public static let all: [Script] = [
        Script(
            name: "層ごとの重みの大きさ",
            code: """
                # 各層の重みの大きさ（フロベニウスノルム）を棒グラフにする
                import mlx.utils

                layers = model.model.layers
                norms = []
                for index, layer in enumerate(layers):
                    weight = layer.mlp.down_proj.weight
                    if hasattr(layer.mlp.down_proj, "scales"):
                        weight = mx.dequantize(weight, layer.mlp.down_proj.scales, layer.mlp.down_proj.biases,
                                               layer.mlp.down_proj.group_size, layer.mlp.down_proj.bits)
                    norms.append(float(mx.linalg.norm(weight.astype(mx.float32))))

                plt.figure(figsize=(8, 3))
                plt.bar(range(len(norms)), norms)
                plt.xlabel("layer")
                plt.ylabel("‖down_proj‖")
                show(plt.gcf())
                """),
        Script(
            name: "トークンの埋め込みの近さ",
            code: """
                # 語の埋め込みベクトルのコサイン類似度を表にする
                words = ["猫", "犬", "東京", "大阪", "量子"]
                ids = [tokenizer.encode(word, add_special_tokens=False)[0] for word in words]
                embedding = model.model.embed_tokens
                vectors = embedding(mx.array(ids)).astype(mx.float32)
                vectors = vectors / mx.linalg.norm(vectors, axis=-1, keepdims=True)
                similarity = (vectors @ vectors.T).tolist()
                show([{"語": word, **{other: round(value, 3) for other, value in zip(words, row)}}
                      for word, row in zip(words, similarity)])
                """),
        Script(
            name: "温度で答えがどう変わるか",
            code: """
                # 同じ質問を、温度を変えて 3 回ずつ生成する
                for temperature in [0.0, 0.7, 1.5]:
                    print(f"--- 温度 {temperature}")
                    for _ in range(3):
                        print(generate("日本で一番高い山は", max_tokens=30, temperature=temperature))
                """),
        Script(
            name: "空のスクリプト",
            code: """
                # model、tokenizer、mx、nn、np、plt、generate(prompt)、show(x) が使える
                print(model.args if hasattr(model, "args") else model)
                """),
    ]
}
