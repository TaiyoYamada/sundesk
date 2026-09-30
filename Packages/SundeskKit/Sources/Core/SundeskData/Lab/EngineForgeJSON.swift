//
//  EngineForgeJSON.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// 工房（フェーズ 7）でエンジンとやりとりする JSON の形（docs/engine-api.md）。

enum ForgeBody: Encodable, Sendable {
    case quantize(QuantizeBody)
    case convert(ConvertBody)
    case fuse(FuseBody)
    case merge(MergeBody)
    case prune(PruneBody)
    case distill(DistillBody)

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .quantize(let body): try body.encode(to: encoder)
        case .convert(let body): try body.encode(to: encoder)
        case .fuse(let body): try body.encode(to: encoder)
        case .merge(let body): try body.encode(to: encoder)
        case .prune(let body): try body.encode(to: encoder)
        case .distill(let body): try body.encode(to: encoder)
        }
    }
}

struct QuantizeOverride: Encodable, Sendable {
    let pattern: String
    let bits: Int?

    // bits が null でも、キーは必ず書く（「量子化しない」の意味になる）
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(bits, forKey: .bits)
    }

    private enum CodingKeys: String, CodingKey {
        case pattern, bits
    }
}

struct QuantizeBody: Encodable, Sendable {
    let model: String
    let outputDir: String
    let method: String
    let bits: Int
    let groupSize: Int
    let mixed: String?
    let overrides: [QuantizeOverride]
    let ternary: Bool
}

struct ConvertQuantize: Encodable, Sendable {
    let bits: Int
    let groupSize: Int
}

struct ConvertBody: Encodable, Sendable {
    let model: String
    let outputDir: String
    let dtype: String
    let quantize: ConvertQuantize?
}

struct FuseBody: Encodable, Sendable {
    let model: String
    let adapter: String
    let outputDir: String
    let dequantize: Bool
}

struct MergeBody: Encodable, Sendable {
    let models: [String]
    let outputDir: String
    let method: String
    /// B の割合（JSON では `t`）。
    let ratio: Double

    private enum CodingKeys: String, CodingKey {
        case models, outputDir, method
        case ratio = "t"
    }
}

struct HeadBody: Encodable, Sendable {
    let layer: Int
    let head: Int
}

struct PruneBody: Encodable, Sendable {
    let model: String
    let outputDir: String
    let dropLayers: [Int]
    let dropHeads: [HeadBody]
}

struct DistillBody: Encodable, Sendable {
    let teacher: String
    let student: String
    let texts: [String]
    let outputDir: String
    let iterations: Int
    let learningRate: Double
    let temperature: Double
    let alpha: Double
    let maxSeqLength: Int
    let batchSize: Int
    /// nil なら生徒の全体を学習する。省くとエンジンの既定（8）になるので、null を必ず書く。
    let loraRank: Int?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(teacher, forKey: .teacher)
        try container.encode(student, forKey: .student)
        try container.encode(texts, forKey: .texts)
        try container.encode(outputDir, forKey: .outputDir)
        try container.encode(iterations, forKey: .iterations)
        try container.encode(learningRate, forKey: .learningRate)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(alpha, forKey: .alpha)
        try container.encode(maxSeqLength, forKey: .maxSeqLength)
        try container.encode(batchSize, forKey: .batchSize)
        try container.encode(loraRank, forKey: .loraRank)
    }

    private enum CodingKeys: String, CodingKey {
        case teacher, student, texts, outputDir, iterations, learningRate, temperature, alpha, maxSeqLength
        case batchSize, loraRank
    }
}

struct ForgeLine: Decodable, Sendable {
    let type: String
    let model: String?
    let stage: String?
    let fraction: Double?
    let message: String?
    let iteration: Int?
    let total: Int?
    let loss: Double?
    /// 先生との分布の差（JSON では `kl`）。
    let divergence: Double?
    /// 交差エントロピー（JSON では `ce`）。
    let crossEntropy: Double?
    let outputDir: String?
    let sizeBytes: Int64?
    let bitsPerWeight: Double?
    let kind: String?

    // キーは snake_case から camelCase に直してから、ここと照らし合わせる
    private enum CodingKeys: String, CodingKey {
        case type, model, stage, fraction, message, iteration, total, loss, outputDir, sizeBytes, bitsPerWeight, kind
        case divergence = "kl"
        case crossEntropy = "ce"
    }
}

struct EvaluateModel: Encodable, Sendable {
    let model: String
    let adapter: String?
}

struct EvaluateBody: Encodable, Sendable {
    let models: [EvaluateModel]
    let texts: [String]
    let prompts: [String]
    let maxTokens: Int
    let seed: Int
}

struct EvaluateLine: Decodable, Sendable {
    let type: String
    let model: String?
    let adapter: String?
    let perplexity: Double?
    let tokens: Int?
    let seconds: Double?
    let tokensPerSecond: Double?
    let sizeBytes: Int64?
    let peakMemoryBytes: Int64?
    let samples: [String]?
}

struct ScratchBody: Encodable, Sendable {
    let session: String
    let code: String
    let model: String?
    let adapter: String?
}

/// 表のセル（数でも文字でもよい）。
struct TableCell: Decodable, Sendable {
    let text: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode(Int.self) {
            text = String(value)
        } else if let value = try? container.decode(Double.self) {
            text = String(format: "%.6g", value)
        } else if let value = try? container.decode(Bool.self) {
            text = value ? "true" : "false"
        } else {
            text = ""
        }
    }
}

struct ScratchLine: Decodable, Sendable {
    let type: String
    let text: String?
    let pngBase64: String?
    let columns: [String]?
    let rows: [[TableCell]]?
    let repr: String?
    let seconds: Double?
    let message: String?
    let traceback: String?
}

struct ResetBody: Encodable {
    let session: String
}

struct ResetResponse: Decodable {
    let reset: Bool
}
