//
//  ChatUseCaseTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Testing

@testable import SundeskDomain

private func chunk(_ id: String, _ text: String, heading: [String] = ["ノート"]) -> NoteChunk {
    NoteChunk(
        id: id, notePath: "\(id).md", noteTitle: heading[0], headingPath: heading, text: text, plainText: text, line: 1)
}

@Suite("RAG の検索")
struct RetrievalTests {
    private func makeRepository() async throws -> KnowledgeRepositorySpy {
        let repository = KnowledgeRepositorySpy()
        try await repository.replace(
            chunks: [
                EmbeddedChunk(chunk: chunk("a", "固有値とは、行列を掛けても向きが変わらないベクトルの倍率。"), contentHash: "a", embedding: nil),
                EmbeddedChunk(chunk: chunk("b", "量子ビットはブロッホ球で表せる。"), contentHash: "b", embedding: nil),
                EmbeddedChunk(chunk: chunk("c", "Swift の並行処理では actor を使う。"), contentHash: "c", embedding: nil),
            ],
            graph: KnowledgeGraph(
                concepts: [
                    Concept(
                        id: 0, label: "ブロッホ球", normalized: "ブロッホ球", score: 1, frequency: 1, pagerank: 1, community: 0)
                ],
                relations: [],
                mentions: [ConceptMention(concept: 0, chunk: "b", count: 2)]),
            embeddingModel: nil)
        return repository
    }

    @Test("語が一致するチャンクを、珍しい語ほど重く見て選ぶ")
    func keywordSearch() async throws {
        let retrieve = RetrieveContextInteractor(repository: try await makeRepository(), engine: KnowledgeEngineSpy())

        let result = try await retrieve("固有値って何？", limit: 2)

        #expect(result.first?.chunk.id == "a")
        #expect(result.first?.sources.contains(.keyword) == true)
    }

    @Test("質問に出てくる概念のチャンクを、知識グラフから選ぶ")
    func graphSearch() async throws {
        let retrieve = RetrieveContextInteractor(repository: try await makeRepository(), engine: KnowledgeEngineSpy())

        let result = try await retrieve("ブロッホ球の見方", limit: 3)

        #expect(result.first?.chunk.id == "b")
        #expect(result.first?.sources == [.keyword, .graph])
    }

    @Test("エンジンが止まっていても、語とグラフで探せる")
    func worksWithoutEngine() async throws {
        let retrieve = RetrieveContextInteractor(
            repository: try await makeRepository(), engine: KnowledgeEngineSpy(failure: .engine("止まっています")))

        #expect(try await retrieve("actor", limit: 1).map(\.chunk.id) == ["c"])
    }
}

@Suite("質問への回答")
struct AskQuestionTests {
    private func makeAsk(
        answer: [String], repository: ChatRepositorySpy, failure: ChatError? = nil
    ) async throws -> AskQuestionInteractor {
        let knowledge = KnowledgeRepositorySpy()
        try await knowledge.replace(
            chunks: [
                EmbeddedChunk(chunk: chunk("a", "固有値の定義。", heading: ["固有値", "定義"]), contentHash: "a", embedding: nil)
            ],
            graph: .empty, embeddingModel: nil)
        return AskQuestionInteractor(
            retrieve: RetrieveContextInteractor(repository: knowledge, engine: KnowledgeEngineSpy()),
            languageModel: LanguageModelStub(tokens: answer, failure: failure), repository: repository)
    }

    @Test("資料に番号を付けて渡し、答えの中の番号を出典として残す")
    func answersWithCitations() async throws {
        let repository = ChatRepositorySpy()
        let ask = try await makeAsk(answer: ["固有値は", "倍率です [1]。"], repository: repository)
        var events: [AnswerEvent] = []

        for try await event in ask("固有値とは？", in: nil, model: "m", settings: GenerationSettings()) {
            events.append(event)
        }

        guard case .finished(let message) = events.last else {
            Issue.record("最後が finished でない: \(events)")
            return
        }
        #expect(message.content == "固有値は倍率です [1]。")
        #expect(message.citations.map(\.number) == [1])
        #expect(message.citations.first?.isCited == true)
        #expect(message.citations.first?.headingPath == ["固有値", "定義"])
        let session = try #require(await repository.sessions().first)
        #expect(session.title == "固有値とは？")
        #expect(try await repository.messages(in: session.id).map(\.role) == [.user, .assistant])
    }

    @Test("プロンプトには、指示と資料、前の会話、質問の順に入れる")
    func promptLayout() {
        let history = [ChatMessage(role: .user, content: "前の質問"), ChatMessage(role: .assistant, content: "前の答え")]

        let prompt = AskQuestionInteractor.prompt(
            question: "今の質問", sources: [chunk("a", "資料の本文", heading: ["固有値", "定義"])], history: history)

        #expect(prompt.map(\.role) == [.system, .user, .assistant, .user])
        #expect(prompt[0].content.contains("[1] 固有値 › 定義（a.md）\n資料の本文"))
        #expect(prompt.last?.content == "今の質問")
    }

    @Test("モデルが失敗したら、質問だけを残して失敗を返す")
    func modelFailure() async throws {
        let repository = ChatRepositorySpy()
        let ask = try await makeAsk(answer: [], repository: repository, failure: .model("モデルを読み込めません"))

        await #expect(throws: ChatError.model("モデルを読み込めません")) {
            for try await _ in ask("質問", in: nil, model: "m", settings: GenerationSettings()) {}
        }
        let session = try #require(await repository.sessions().first)
        #expect(try await repository.messages(in: session.id).map(\.role) == [.user])
    }

    @Test("題名は最初の行の 40 文字まで")
    func title() {
        #expect(AskQuestionInteractor.title(for: "短い質問\n2 行目") == "短い質問")
        #expect(AskQuestionInteractor.title(for: String(repeating: "あ", count: 50)).count == 41)
    }
}

// MARK: - テスト用の偽物

actor ChatRepositorySpy: ChatRepository {
    private var storedSessions: [ChatSession] = []
    private var storedMessages: [UUID: [ChatMessage]] = [:]

    func sessions() async throws(ChatError) -> [ChatSession] { storedSessions }

    func messages(in sessionID: UUID) async throws(ChatError) -> [ChatMessage] { storedMessages[sessionID] ?? [] }

    func createSession(title: String, model: String) async throws(ChatError) -> ChatSession {
        let session = ChatSession(id: UUID(), title: title, model: model, createdAt: .now, updatedAt: .now)
        storedSessions.append(session)
        return session
    }

    func append(_ message: ChatMessage, to sessionID: UUID) async throws(ChatError) {
        storedMessages[sessionID, default: []].append(message)
    }

    func deleteSession(_ id: UUID) async throws(ChatError) {
        storedSessions.removeAll { $0.id == id }
    }

    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

struct LanguageModelStub: LanguageModelService {
    let tokens: [String]
    var failure: ChatError?

    func availableModels() async -> [ChatModelOption] { [] }

    func generate(
        _ messages: [PromptMessage], model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, any Error> {
        AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            continuation.yield(.loading)
            for token in tokens { continuation.yield(.token(token)) }
            continuation.yield(.done(tokensPerSecond: 10))
            continuation.finish()
        }
    }
}

@Suite("ThinkingFilter")
struct ThinkingFilterTests {
    @Test("考える過程を、タグが途中で切れていても取り除く")
    func stripsAcrossChunks() {
        var filter = ThinkingFilter()
        var output = ""
        for piece in ["<th", "ink>考え", "中</thi", "nk>\n\n答え", "は [1]", "。<"] {
            output += filter.feed(piece)
        }
        output += filter.finish()

        #expect(output == "\n\n答えは [1]。<")
        #expect(ThinkingFilter.strip("<think>a</think>\n答え") == "答え")
        #expect(ThinkingFilter.strip("考えずに答える") == "考えずに答える")
        #expect(ThinkingFilter.strip("<think>途中で終わった").isEmpty)
    }
}
