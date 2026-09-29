//
//  ChatModels.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// 回答の根拠にしたノートの節。番号は回答の中の `[1]` と対応する。
public struct Citation: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public let chunkID: String
    public let notePath: String
    public let noteTitle: String
    public let headingPath: [String]
    public let line: Int
    public let snippet: String
    /// 回答の中で実際に番号を示したか。
    public let isCited: Bool

    public init(
        number: Int, chunkID: String, notePath: String, noteTitle: String, headingPath: [String], line: Int,
        snippet: String, isCited: Bool
    ) {
        self.number = number
        self.chunkID = chunkID
        self.notePath = notePath
        self.noteTitle = noteTitle
        self.headingPath = headingPath
        self.line = line
        self.snippet = snippet
        self.isCited = isCited
    }

    func cited(_ isCited: Bool) -> Citation {
        Citation(
            number: number, chunkID: chunkID, notePath: notePath, noteTitle: noteTitle, headingPath: headingPath,
            line: line, snippet: snippet, isCited: isCited)
    }
}

public struct ChatMessage: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let citations: [Citation]
    public let createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, content: String, citations: [Citation] = [], createdAt: Date = .now)
    {
        self.id = id
        self.role = role
        self.content = content
        self.citations = citations
        self.createdAt = createdAt
    }
}

public struct ChatSession: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    /// 使ったモデル。
    public let model: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, title: String, model: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 会話に使えるモデル。
public struct ChatModelOption: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable {
        /// Apple のオンデバイスモデル（Foundation Models）。
        case apple
        /// Hugging Face の MLX のモデル（Python のエンジンで動かす）。
        case mlx
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// 手元にあるか（なければ最初に使うときにダウンロードする）。
    public let isDownloaded: Bool
    /// 使えない理由（Apple Intelligence が有効でない、など）。
    public let unavailableReason: String?

    public init(id: String, name: String, kind: Kind, isDownloaded: Bool, unavailableReason: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isDownloaded = isDownloaded
        self.unavailableReason = unavailableReason
    }

    /// Apple のオンデバイスモデルの ID。
    public static let appleID = "apple.foundation-models"
    /// 既定の MLX のモデル（16GB でも軽く動く、日本語の得意な指示モデル）。
    public static let defaultMLXID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
}

/// 会話のモデルに渡す 1 つの発言。
public struct PromptMessage: Hashable, Sendable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct GenerationSettings: Hashable, Sendable {
    public var temperature: Double
    public var maxTokens: Int
    /// 考える過程（Qwen3 の `<think>`）を許すか。小さなモデルでは考えるだけで上限に達し、答えが空になりやすい。
    public var thinking: Bool

    public init(temperature: Double = 0.4, maxTokens: Int = 1200, thinking: Bool = false) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.thinking = thinking
    }
}

/// 生成の途中経過。
public enum GenerationEvent: Hashable, Sendable {
    /// モデルを読み込み始めた（初回は時間がかかる）。
    case loading
    case token(String)
    case done(tokensPerSecond: Double?)
}

/// 質問への答えの途中経過。
public enum AnswerEvent: Hashable, Sendable {
    /// 会話が決まった（新しい会話なら、ここで作ったもの）。
    case session(ChatSession)
    /// 根拠の候補を探し終えた。
    case retrieved([Citation])
    case loadingModel
    /// モデルが考えている（答えの前の、考える過程を出している）。
    case thinking
    case token(String)
    /// 答え終えて保存した。
    case finished(ChatMessage)
}

public enum ChatError: Error, Equatable, Sendable {
    case storage(String)
    case model(String)

    public var message: String {
        switch self {
        case .storage(let message): "会話を保存できませんでした: \(message)"
        case .model(let message): message
        }
    }
}

/// 会話を保存する。
public protocol ChatRepository: Sendable {
    func sessions() async throws(ChatError) -> [ChatSession]
    func messages(in sessionID: UUID) async throws(ChatError) -> [ChatMessage]
    func createSession(title: String, model: String) async throws(ChatError) -> ChatSession
    func append(_ message: ChatMessage, to sessionID: UUID) async throws(ChatError)
    func deleteSession(_ id: UUID) async throws(ChatError)
    func changes() -> AsyncStream<Void>
}

/// 文章を生成するモデル。Apple のオンデバイスモデルと、エンジンの MLX のモデルをまとめて扱う。
public protocol LanguageModelService: Sendable {
    func availableModels() async -> [ChatModelOption]
    func generate(
        _ messages: [PromptMessage], model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, any Error>
}
