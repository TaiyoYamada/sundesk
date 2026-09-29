//
//  ChatViewModel.swift
//  ChatFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// ノートを根拠に答えるチャット。会話の履歴、質問、答えの逐次表示、出典。
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var sessions: [ChatSessionItem] = []
    public private(set) var selectedSessionID: UUID?
    public private(set) var messages: [ChatMessageItem] = []
    public private(set) var models: [ChatModelItem] = []
    public var selectedModelID: String = ChatModelOption.appleID
    public var input = ""
    /// 答えている途中の文章。
    public private(set) var streamingAnswer = ""
    /// 答えている途中に見つけた出典の候補。
    public private(set) var streamingCitations: [CitationItem] = []
    /// 答えている途中の様子（「資料を探しています」など）。
    public private(set) var status: String?
    public var errorMessage: String?
    public private(set) var build: String?
    public var temperature = 0.4

    public var isAnswering: Bool { answerTask != nil }
    public var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering }

    /// インスペクタに出す出典（答えている途中なら途中のもの、そうでなければ最後の答えのもの）。
    public var inspectedCitations: [CitationItem] {
        if isAnswering { return streamingCitations }
        return messages.last { $0.role == .assistant }?.citations ?? []
    }

    @ObservationIgnored private let ask: any AskQuestionUseCase
    @ObservationIgnored private let listSessions: any ListChatSessionsUseCase
    @ObservationIgnored private let loadMessages: any LoadChatMessagesUseCase
    @ObservationIgnored private let deleteSession: any DeleteChatSessionUseCase
    @ObservationIgnored private let observeSessions: any ObserveChatSessionsUseCase
    @ObservationIgnored private let listModels: any ListChatModelsUseCase
    @ObservationIgnored private let rebuildKnowledge: any RebuildKnowledgeUseCase
    @ObservationIgnored private let observeBuild: any ObserveKnowledgeBuildUseCase
    @ObservationIgnored private var answerTask: Task<Void, Never>?
    @ObservationIgnored private var currentSession: ChatSession?
    @ObservationIgnored private var sessionModels: [UUID: ChatSession] = [:]

    public init(
        ask: any AskQuestionUseCase,
        listSessions: any ListChatSessionsUseCase,
        loadMessages: any LoadChatMessagesUseCase,
        deleteSession: any DeleteChatSessionUseCase,
        observeSessions: any ObserveChatSessionsUseCase,
        listModels: any ListChatModelsUseCase,
        rebuildKnowledge: any RebuildKnowledgeUseCase,
        observeBuild: any ObserveKnowledgeBuildUseCase
    ) {
        self.ask = ask
        self.listSessions = listSessions
        self.loadMessages = loadMessages
        self.deleteSession = deleteSession
        self.observeSessions = observeSessions
        self.listModels = listModels
        self.rebuildKnowledge = rebuildKnowledge
        self.observeBuild = observeBuild
    }

    // MARK: - 読み込み

    public func observe() async {
        await reloadSessions()
        for await _ in observeSessions() {
            await reloadSessions()
        }
    }

    public func observeBuildProgress() async {
        for await step in await observeBuild() {
            build = step.flatMap(Self.buildTitle)
        }
    }

    /// 使えるモデルを読み直す。選んでいるモデルが使えなければ、使えるものに切り替える。
    public func loadModels() async {
        let options = await listModels()
        models = options.map(ChatModelItem.init)
        if !models.contains(where: { $0.id == selectedModelID && $0.isAvailable }),
            let first = models.first(where: \.isAvailable)
        {
            selectedModelID = first.id
        }
    }

    private func reloadSessions() async {
        let loaded = (try? await listSessions()) ?? []
        sessionModels = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sessions = loaded.map(ChatSessionItem.init)
    }

    // MARK: - 会話

    public func newSession() {
        stop()
        selectedSessionID = nil
        currentSession = nil
        messages = []
        errorMessage = nil
    }

    public func select(sessionID: UUID) async {
        guard sessionID != selectedSessionID else { return }
        stop()
        selectedSessionID = sessionID
        currentSession = sessionModels[sessionID]
        if let model = currentSession?.model, models.contains(where: { $0.id == model }) { selectedModelID = model }
        messages = ((try? await loadMessages(sessionID)) ?? []).map(ChatMessageItem.init)
    }

    public func delete(sessionID: UUID) async {
        do {
            try await deleteSession(sessionID)
            if selectedSessionID == sessionID { newSession() }
        } catch {
            errorMessage = error.message
        }
    }

    /// 入力した質問を送る。答えは少しずつ届く。
    public func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        input = ""
        errorMessage = nil
        messages.append(ChatMessageItem(ChatMessage(role: .user, content: question)))
        streamingAnswer = ""
        streamingCitations = []
        status = "資料を探しています"
        let stream = ask(
            question, in: currentSession, model: selectedModelID,
            settings: GenerationSettings(temperature: temperature))
        answerTask = Task { await consume(stream) }
    }

    /// 答えを途中で止める。
    public func stop() {
        answerTask?.cancel()
        answerTask = nil
        status = nil
    }

    private func consume(_ stream: AsyncThrowingStream<AnswerEvent, any Error>) async {
        do {
            for try await event in stream {
                switch event {
                case .session(let session):
                    currentSession = session
                    selectedSessionID = session.id
                case .retrieved(let citations):
                    streamingCitations = citations.map(CitationItem.init)
                    status = "考えています"
                case .loadingModel:
                    status = "モデルを読み込んでいます（初回はダウンロードに時間がかかります）"
                case .thinking:
                    status = "考えています"
                case .token(let text):
                    status = nil
                    streamingAnswer += streamingAnswer.isEmpty ? String(text.drop { $0.isWhitespace }) : text
                case .finished(let message):
                    messages.append(ChatMessageItem(message))
                    streamingAnswer = ""
                }
            }
        } catch is CancellationError {
            // 止めたときは、途中までの答えを残す
        } catch let error as ChatError {
            errorMessage = error.message
        } catch {
            errorMessage = "答えられませんでした: \(error.localizedDescription)"
        }
        if !streamingAnswer.isEmpty {
            messages.append(ChatMessageItem(ChatMessage(role: .assistant, content: streamingAnswer)))
            streamingAnswer = ""
        }
        status = nil
        answerTask = nil
    }

    // MARK: - 知識

    public func rebuild() async {
        do {
            try await rebuildKnowledge()
        } catch {
            errorMessage = error.message
        }
    }

    private static func buildTitle(_ step: KnowledgeBuildStep) -> String? {
        switch step {
        case .readingNotes(let done, let total): "ノートを読んでいます（\(done)/\(total)）"
        case .embedding(let done, let total): "埋め込みを計算しています（\(done)/\(total)）"
        case .buildingGraph: "知識グラフを作っています"
        case .saving: "保存しています"
        case .finished: nil
        }
    }
}

// MARK: - 表示用の型

public struct ChatSessionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let date: String

    init(_ session: ChatSession) {
        id = session.id
        title = session.title
        date = session.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

public struct ChatMessageItem: Identifiable, Hashable, Sendable {
    public enum Role: Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let content: String
    public let citations: [CitationItem]

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role == .user ? .user : .assistant
        content = message.content
        citations = message.citations.map(CitationItem.init)
    }
}

public struct CitationItem: Identifiable, Hashable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let path: String
    public let title: String
    /// 見出しの階層（ノートのタイトルを除く）。
    public let heading: String
    public let line: Int
    public let snippet: String
    public let isCited: Bool

    init(_ citation: Citation) {
        number = citation.number
        path = citation.notePath
        title = citation.noteTitle
        heading = citation.headingPath.dropFirst().joined(separator: " › ")
        line = citation.line
        snippet = citation.snippet
        isCited = citation.isCited
    }
}

public struct ChatModelItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String?
    public let isAvailable: Bool

    init(_ option: ChatModelOption) {
        id = option.id
        name = option.name
        isAvailable = option.unavailableReason == nil
        detail =
            if let reason = option.unavailableReason {
                reason
            } else if option.kind == .mlx && !option.isDownloaded {
                "最初に使うときにダウンロードします"
            } else {
                nil
            }
    }
}
