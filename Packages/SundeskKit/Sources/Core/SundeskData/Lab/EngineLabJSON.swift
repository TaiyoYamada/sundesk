//
//  EngineLabJSON.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDomain

// エンジンとやりとりする JSON の形（docs/engine-api.md）。キーは snake_case に自動で直す。

struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let kind: String
        let sizeBytes: Int64
        let path: String
    }

    let models: [Model]
}

struct DownloadRequest: Encodable, Sendable {
    let id: String
}

struct DownloadLine: Decodable, Sendable {
    let type: String
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let path: String?
}

struct DeletedResponse: Decodable {
    let deleted: Bool
}

struct LoadedResponse: Decodable {
    let llm: String?
    let image: String?
    let embedding: String?
    let adapter: String?
}

struct UnloadRequest: Encodable {
    let kind: String
}

struct UnloadResponse: Decodable {
    let unloaded: [String]
}

struct TokenizeRequest: Encodable {
    let model: String
    let text: String
}

struct TokenizeResponse: Decodable {
    struct Token: Decodable {
        let id: Int
        let text: String
        let start: Int?
        let end: Int?
    }

    let tokens: [Token]
}

struct TokenItem: Decodable, Sendable {
    let id: Int
    let text: String
    let probability: Double

    var value: TokenProbability { TokenProbability(id: id, text: text, probability: probability) }
}

struct NextTokenRequest: Encodable {
    let model: String
    let prompt: String
    let chatTemplate: Bool
    let topK: Int
    let temperature: Double
}

struct NextTokenResponse: Decodable {
    struct Token: Decodable {
        let id: Int
        let text: String
        let probability: Double
        let logit: Double?

        var value: TokenProbability { TokenProbability(id: id, text: text, probability: probability) }
    }

    let tokens: [Token]
    let entropy: Double
}

struct GenerateRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let chatTemplate: Bool
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let topK: Int
    let seed: Int?
    let alternatives: Int
    let adapter: String?
}

struct GenerateLine: Decodable, Sendable {
    let type: String
    let id: Int?
    let text: String?
    let probability: Double?
    let alternatives: [TokenItem]?
    let tokensPerSecond: Double?
}

struct PromptRequest: Encodable {
    let model: String
    let prompt: String
    let chatTemplate: Bool
}

struct LayerRequest: Encodable {
    let model: String
    let prompt: String
    let chatTemplate: Bool
    let layer: Int
}

struct TopKRequest: Encodable {
    let model: String
    let prompt: String
    let chatTemplate: Bool
    let topK: Int
}

struct PlainToken: Decodable {
    let id: Int
    let text: String
}

struct AttentionResponse: Decodable {
    let tokens: [PlainToken]
    let numLayers: Int
    let numHeads: Int
    let layer: Int
    let heads: [[[Double]]]
    let mean: [[Double]]
}

struct LogitLensPosition: Decodable {
    let top: [TokenItem]
}

struct LogitLensResponse: Decodable {
    struct Layer: Decodable {
        let layer: Int
        let positions: [LogitLensPosition]
    }

    let tokens: [PlainToken]
    let numLayers: Int
    let layers: [Layer]
}

struct ActivationsResponse: Decodable {
    let tokens: [PlainToken]
    let numLayers: Int
    let norms: [[Double]]
}

struct LoRARequest: Encodable, Sendable {
    let model: String
    let texts: [String]
    let adapterPath: String
    let iterations: Int
    let rank: Int
    let learningRate: Double
    let batchSize: Int
    let maxSeqLength: Int
    let numLayers: Int
}

struct LoRALine: Decodable, Sendable {
    let type: String
    let iteration: Int?
    let total: Int?
    let trainLoss: Double?
    let valLoss: Double?
    let adapterPath: String?
}

struct SteeringVectorRequest: Encodable {
    let model: String
    let layer: Int
    let positive: [String]
    let negative: [String]
}

struct SteeringVectorResponse: Decodable {
    let layer: Int
    let vector: [Float]
    let norm: Double
}

struct SteeringRequest: Encodable {
    let model: String
    let prompt: String
    let chatTemplate: Bool
    let layer: Int
    let vector: [Float]
    let strength: Double
    let maxTokens: Int
    let temperature: Double
    let seed: Int
}

struct SteeringResponse: Decodable {
    let baseline: String
    let steered: String
}

struct ImageModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let name: String
        let repo: String
        let downloaded: Bool
        let defaultSteps: Int
        let defaultSize: Int
    }

    let models: [Model]
}

struct ImageGenerateRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let width: Int
    let height: Int
    let steps: Int?
    let seed: Int?
    let quantize: Int?
    let outputPath: String
}

struct ImageLine: Decodable, Sendable {
    let type: String
    let step: Int?
    let total: Int?
    let path: String?
    let seed: Int?
    let seconds: Double?
}
