//
//  ImageModels.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

public struct ImageModelOption: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let repository: String
    public let isDownloaded: Bool
    public let defaultSteps: Int
    public let defaultSize: Int

    public init(id: String, name: String, repository: String, isDownloaded: Bool, defaultSteps: Int, defaultSize: Int) {
        self.id = id
        self.name = name
        self.repository = repository
        self.isDownloaded = isDownloaded
        self.defaultSteps = defaultSteps
        self.defaultSize = defaultSize
    }
}

public struct ImageRequest: Hashable, Sendable {
    public var model: String
    public var prompt: String
    public var width: Int
    public var height: Int
    /// nil ならモデルの既定。
    public var steps: Int?
    /// nil なら毎回変える。
    public var seed: Int?
    public var quantize: Int?

    public init(
        model: String, prompt: String, width: Int = 1024, height: Int = 1024, steps: Int? = nil, seed: Int? = nil,
        quantize: Int? = 4
    ) {
        self.model = model
        self.prompt = prompt
        self.width = width
        self.height = height
        self.steps = steps
        self.seed = seed
        self.quantize = quantize
    }
}

public enum ImageGenerationEvent: Hashable, Sendable {
    case loading
    case progress(step: Int, total: Int)
    case done(GeneratedImage)
}

/// 生成した画像の記録。
public struct GeneratedImage: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let model: String
    public let prompt: String
    public let width: Int
    public let height: Int
    public let steps: Int?
    public let seed: Int
    public let path: String
    public let seconds: Double
    public let createdAt: Date

    public init(
        id: UUID, model: String, prompt: String, width: Int, height: Int, steps: Int?, seed: Int, path: String,
        seconds: Double, createdAt: Date
    ) {
        self.id = id
        self.model = model
        self.prompt = prompt
        self.width = width
        self.height = height
        self.steps = steps
        self.seed = seed
        self.path = path
        self.seconds = seconds
        self.createdAt = createdAt
    }
}
