//
//  LabDisplayModels.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

// View に渡す表示用の型。

public struct TokenItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let tokenID: Int
    /// 見やすくした文字（空白や改行を記号にする）。
    public let text: String

    init(index: Int, piece: TokenPiece) {
        id = index
        tokenID = piece.id
        text = TokenText.visible(piece.text)
    }
}

public struct ProbabilityItem: Identifiable, Hashable, Sendable {
    public var id: Int { tokenID }
    public let tokenID: Int
    public let text: String
    public let probability: Double

    init(_ token: TokenProbability) {
        tokenID = token.id
        text = TokenText.visible(token.text)
        probability = token.probability
    }
}

public struct GeneratedTokenItem: Identifiable, Hashable, Sendable {
    public let id: Int
    /// そのままの文字（本文の組み立てに使う）。
    public let rawText: String
    public let text: String
    public let probability: Double
    public let alternatives: [ProbabilityItem]

    init(index: Int, _ token: GeneratedToken) {
        id = index
        rawText = token.token.text
        text = TokenText.visible(token.token.text)
        probability = token.token.probability
        alternatives = token.alternatives.map(ProbabilityItem.init)
    }
}

public struct AttentionItem: Hashable, Sendable {
    public let tokens: [String]
    public let layerCount: Int
    public let headCount: Int
    public let layer: Int
    public let heads: [[[Double]]]
    public let mean: [[Double]]

    init(_ map: AttentionMap) {
        tokens = map.tokens.map(TokenText.visible)
        layerCount = map.layerCount
        headCount = map.headCount
        layer = map.layer
        heads = map.heads
        mean = map.mean
    }

    /// 表示する行列（ヘッドを選んでいなければ平均）。
    public func matrix(head: Int?) -> [[Double]] {
        guard let head, heads.indices.contains(head) else { return mean }
        return heads[head]
    }
}

public struct LogitLensItem: Hashable, Sendable {
    public struct Cell: Hashable, Sendable {
        public let text: String
        public let probability: Double
    }

    public let tokens: [String]
    /// `cells[layer][position]`（一番上の予測）。
    public let cells: [[Cell]]

    init(_ lens: LogitLens) {
        tokens = lens.tokens.map(TokenText.visible)
        cells = lens.layers.map { layer in
            layer.map { top in
                Cell(text: TokenText.visible(top.first?.text ?? ""), probability: top.first?.probability ?? 0)
            }
        }
    }
}

public struct ActivationsItem: Hashable, Sendable {
    public let tokens: [String]
    public let norms: [[Double]]
    public let maxNorm: Double

    init(_ activations: ActivationNorms) {
        tokens = activations.tokens.map(TokenText.visible)
        norms = activations.norms
        maxNorm = activations.norms.flatMap { $0 }.max() ?? 1
    }
}

public struct LossPoint: Identifiable, Hashable, Sendable {
    public var id: Int { iteration }
    public let iteration: Int
    public let loss: Double
}

public struct AdapterItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let model: String
    public let detail: String

    init(_ adapter: Adapter) {
        id = adapter.id
        name = adapter.name
        model = adapter.model
        let loss = adapter.finalLoss.map { String(format: "損失 %.3f・", $0) } ?? ""
        detail = "\(adapter.source)・\(loss)\(adapter.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

public struct SteeringItem: Hashable, Sendable {
    public let baseline: String
    public let steered: String
    /// ベクトルの大きさ。
    public let norm: String
}

public struct ExperimentItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: String
    public let model: String
    public let prompt: String
    public let parameters: String
    public let summary: String
    public let date: String

    init(_ experiment: Experiment) {
        id = experiment.id
        kind =
            switch experiment.kind {
            case .tokenize: "トークン"
            case .nextToken: "次のトークン"
            case .generate: "生成"
            case .attention: "Attention"
            case .logitLens: "Logit lens"
            case .activations: "活性"
            case .lora: "LoRA"
            case .steering: "Steering"
            case .forge: "工房"
            case .evaluate: "評価"
            case .script: "スクリプト"
            }
        model = experiment.model.split(separator: "/").last.map(String.init) ?? experiment.model
        prompt = experiment.prompt
        parameters = experiment.parameters.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            .joined(separator: "、")
        summary = experiment.summary
        date = experiment.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

/// トークンの文字を見やすくする（空白は ␣、改行は ↵）。
enum TokenText {
    static func visible(_ text: String) -> String {
        text.replacing(" ", with: "␣").replacing("\n", with: "↵").replacing("\t", with: "⇥")
    }
}
