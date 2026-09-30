//
//  LanguageModelRouter.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import FoundationModels
import SundeskDomain
import SundeskEngineClient

/// 生成を、Apple のオンデバイスモデル（Foundation Models）か、エンジンの MLX のモデルに振り分ける。
public struct LanguageModelRouter: LanguageModelService {
    private let process: EngineProcess

    public init(process: EngineProcess) {
        self.process = process
    }

    public func availableModels() async -> [ChatModelOption] {
        var options = [AppleLanguageModel.option()]
        var local: [String] = []
        // エンジンが動いているときだけ、手元のモデルを聞く（一覧のためにエンジンを起動しない）
        if let client = await process.client,
            let response = try? await client.get("models", as: ModelsResponse.self, timeout: 10)
        {
            local = response.models.filter { $0.kind == "llm" }.map(\.id)
        }
        let ids = [ChatModelOption.defaultMLXID] + local.filter { $0 != ChatModelOption.defaultMLXID }.sorted()
        options += ids.map { id in
            ChatModelOption(
                id: id, name: id.split(separator: "/").last.map(String.init) ?? id, kind: .mlx,
                isDownloaded: local.contains(id))
        }
        return options
    }

    public func generate(
        _ messages: [PromptMessage], model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, any Error> {
        if model == ChatModelOption.appleID {
            return AppleLanguageModel.generate(messages, settings: settings)
        }
        return generateWithEngine(messages, model: model, settings: settings)
    }

    private func generateWithEngine(
        _ messages: [PromptMessage], model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, any Error> {
        let process = process
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let client: EngineClient
                    do {
                        client = try await process.runningClient()
                    } catch let error as EngineProcessError {
                        throw ChatError.model(EngineMapper.failure(from: error).message)
                    }
                    try await EngineModelEnsurer.shared.ensure(model, client: client) {
                        continuation.yield(.loading)
                    }
                    let request = ChatRequest(
                        model: model, messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                        maxTokens: settings.maxTokens, temperature: settings.temperature, topP: 0.95, adapter: nil,
                        thinking: settings.thinking)
                    for try await event in client.stream("chat", body: request, as: ChatEvent.self) {
                        switch event.type {
                        case "loading": continuation.yield(.loading)
                        case "token": continuation.yield(.token(event.text ?? ""))
                        case "done": continuation.yield(.done(tokensPerSecond: event.tokensPerSecond))
                        default: break
                        }
                    }
                    continuation.finish()
                } catch let error as EngineClientError {
                    continuation.finish(throwing: ChatError.model(error.message))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Apple のオンデバイスモデル。
enum AppleLanguageModel {
    static func option() -> ChatModelOption {
        let reason: String? =
            switch SystemLanguageModel.default.availability {
            case .available: nil
            case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence が有効になっていません"
            case .unavailable(.deviceNotEligible): "この Mac では使えません"
            case .unavailable(.modelNotReady): "モデルの準備ができていません（ダウンロード中など）"
            case .unavailable: "使えません"
            }
        return ChatModelOption(
            id: ChatModelOption.appleID, name: "Apple（オンデバイス）", kind: .apple, isDownloaded: true,
            unavailableReason: reason)
    }

    static func generate(
        _ messages: [PromptMessage], settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let reason = option().unavailableReason { throw ChatError.model(reason) }
                    let instructions = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
                    // 前の発言は、指示のあとに会話の記録として添える
                    let history = messages.dropLast().filter { $0.role != .system }
                        .map { "\($0.role == .user ? "利用者" : "アシスタント"): \($0.content)" }
                        .joined(separator: "\n")
                    let session = LanguageModelSession(
                        instructions: history.isEmpty ? instructions : instructions + "\n\n# これまでの会話\n" + history)
                    let prompt = messages.last?.content ?? ""
                    var previous = ""
                    let options = GenerationOptions(
                        temperature: settings.temperature, maximumResponseTokens: settings.maxTokens)
                    for try await snapshot in session.streamResponse(to: prompt, options: options) {
                        let content = snapshot.content
                        if content.hasPrefix(previous) {
                            continuation.yield(.token(String(content.dropFirst(previous.count))))
                        }
                        previous = content
                    }
                    continuation.yield(.done(tokensPerSecond: nil))
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(
                        throwing: ChatError.model("Apple のモデルで生成できませんでした: \(error.localizedDescription)"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - JSON

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let adapter: String?
    let thinking: Bool
}

private struct ChatEvent: Decodable, Sendable {
    let type: String
    let text: String?
    let tokensPerSecond: Double?
}
