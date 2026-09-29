//
//  ChatUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - 質問する

public protocol AskQuestionUseCase: Sendable {
    /// ノートを根拠に答える。`session` が nil なら新しい会話を作る。質問と答えは会話に保存する。
    func callAsFunction(
        _ question: String, in session: ChatSession?, model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<AnswerEvent, any Error>
}

public struct AskQuestionInteractor: AskQuestionUseCase {
    private let retrieve: any RetrieveContextUseCase
    private let languageModel: any LanguageModelService
    private let repository: any ChatRepository
    /// 根拠にする節の数。
    private let sourceLimit: Int
    /// 前の発言をいくつまで渡すか。
    private let historyLimit: Int

    public init(
        retrieve: any RetrieveContextUseCase,
        languageModel: any LanguageModelService,
        repository: any ChatRepository,
        sourceLimit: Int = 6,
        historyLimit: Int = 6
    ) {
        self.retrieve = retrieve
        self.languageModel = languageModel
        self.repository = repository
        self.sourceLimit = sourceLimit
        self.historyLimit = historyLimit
    }

    public func callAsFunction(
        _ question: String, in session: ChatSession?, model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<AnswerEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await answer(question, in: session, model: model, settings: settings, to: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func answer(
        _ question: String, in existing: ChatSession?, model: String, settings: GenerationSettings,
        to continuation: AsyncThrowingStream<AnswerEvent, any Error>.Continuation
    ) async throws {
        let session: ChatSession
        if let existing {
            session = existing
        } else {
            session = try await repository.createSession(title: Self.title(for: question), model: model)
        }
        continuation.yield(.session(session))
        let history = try await repository.messages(in: session.id)
        try await repository.append(ChatMessage(role: .user, content: question), to: session.id)

        let retrieved = (try? await retrieve(question, limit: sourceLimit)) ?? []
        let citations = retrieved.enumerated().map { index, item in
            Citation(
                number: index + 1, chunkID: item.chunk.id, notePath: item.chunk.notePath,
                noteTitle: item.chunk.noteTitle, headingPath: item.chunk.headingPath, line: item.chunk.line,
                snippet: String(item.chunk.plainText.replacing(/\s+/, with: " ").prefix(120)), isCited: false)
        }
        continuation.yield(.retrieved(citations))

        let messages = Self.prompt(
            question: question, sources: retrieved.map(\.chunk), history: history.suffix(historyLimit))
        var answer = ""
        for try await event in languageModel.generate(messages, model: model, settings: settings) {
            switch event {
            case .loading:
                continuation.yield(.loadingModel)
            case .token(let text):
                answer += text
                continuation.yield(.token(text))
            case .done:
                break
            }
        }

        let cited = Self.citedNumbers(in: answer)
        let message = ChatMessage(
            role: .assistant, content: answer, citations: citations.map { $0.cited(cited.contains($0.number)) })
        try await repository.append(message, to: session.id)
        continuation.yield(.finished(message))
    }

    /// 会話の題名（最初の質問の頭）。
    static func title(for question: String) -> String {
        let line = question.split(separator: "\n").first.map(String.init) ?? question
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    /// 回答の中の `[1]` や `[2][3]` の番号。
    static func citedNumbers(in answer: String) -> Set<Int> {
        Set(answer.matches(of: /\[(\d{1,2})\]/).compactMap { Int($0.output.1) })
    }

    /// モデルに渡す発言。資料は番号を付けて、システムの指示に入れる。
    static func prompt(question: String, sources: [NoteChunk], history: some Collection<ChatMessage>) -> [PromptMessage]
    {
        var system = """
            あなたは、利用者の学習ノートを参照して質問に答えるアシスタントです。
            下の資料を根拠に、日本語で簡潔に答えてください。
            根拠にした資料は、文の終わりに [1] のように番号で示してください。
            資料に答えがなければ、推測で補わず、資料には書かれていないと伝えてください。
            """
        if sources.isEmpty {
            system += "\n\n（関係する資料は見つかりませんでした）"
        } else {
            system += "\n\n# 資料\n"
            for (index, chunk) in sources.enumerated() {
                system += "\n[\(index + 1)] \(chunk.headingPath.joined(separator: " › "))（\(chunk.notePath)）\n"
                system += chunk.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
        }
        var messages = [PromptMessage(role: .system, content: system)]
        messages += history.filter { $0.role != .system }.map { PromptMessage(role: $0.role, content: $0.content) }
        messages.append(PromptMessage(role: .user, content: question))
        return messages
    }
}

// MARK: - 会話の履歴

public protocol ListChatSessionsUseCase: Sendable {
    func callAsFunction() async throws(ChatError) -> [ChatSession]
}

public protocol LoadChatMessagesUseCase: Sendable {
    func callAsFunction(_ sessionID: UUID) async throws(ChatError) -> [ChatMessage]
}

public protocol DeleteChatSessionUseCase: Sendable {
    func callAsFunction(_ sessionID: UUID) async throws(ChatError)
}

public protocol ObserveChatSessionsUseCase: Sendable {
    func callAsFunction() -> AsyncStream<Void>
}

public protocol ListChatModelsUseCase: Sendable {
    func callAsFunction() async -> [ChatModelOption]
}

/// 会話の履歴の読み書き（題名の一覧、中身、削除、変化の見張り）と、使えるモデルの一覧。
public struct ChatHistoryInteractor: ListChatSessionsUseCase, LoadChatMessagesUseCase, DeleteChatSessionUseCase,
    ObserveChatSessionsUseCase, ListChatModelsUseCase
{
    private let repository: any ChatRepository
    private let languageModel: any LanguageModelService

    public init(repository: any ChatRepository, languageModel: any LanguageModelService) {
        self.repository = repository
        self.languageModel = languageModel
    }

    public func callAsFunction() async throws(ChatError) -> [ChatSession] {
        try await repository.sessions()
    }

    public func callAsFunction(_ sessionID: UUID) async throws(ChatError) -> [ChatMessage] {
        try await repository.messages(in: sessionID)
    }

    public func callAsFunction(_ sessionID: UUID) async throws(ChatError) {
        try await repository.deleteSession(sessionID)
    }

    public func callAsFunction() -> AsyncStream<Void> {
        repository.changes()
    }

    public func callAsFunction() async -> [ChatModelOption] {
        await languageModel.availableModels()
    }
}
