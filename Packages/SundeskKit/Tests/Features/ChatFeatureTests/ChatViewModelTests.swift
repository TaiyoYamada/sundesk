//
//  ChatViewModelTests.swift
//  ChatFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import ChatFeature
import Foundation
import SundeskDomain
import Testing

@MainActor
@Suite("ChatViewModel")
struct ChatViewModelTests {
    private static let citation = Citation(
        number: 1, chunkID: "a#0", notePath: "数学/固有値.md", noteTitle: "固有値", headingPath: ["固有値", "定義"], line: 7,
        snippet: "固有値とは", isCited: true)

    private func makeViewModel(events: [AnswerEvent], failure: (any Error)? = nil) -> ChatViewModel {
        let history = HistoryStub()
        return ChatViewModel(
            ask: AskStub(events: events, failure: failure), listSessions: history, loadMessages: history,
            deleteSession: history, observeSessions: history, listModels: history, rebuildKnowledge: RebuildStub(),
            observeBuild: RebuildStub())
    }

    private func waitUntilIdle(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 where viewModel.isAnswering {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("送ると質問を出し、答えを受け取って出典つきで残す")
    func sendsAndReceives() async {
        let session = ChatSession(id: UUID(), title: "固有値とは？", model: "m", createdAt: .now, updatedAt: .now)
        let answer = ChatMessage(role: .assistant, content: "倍率です [1]。", citations: [Self.citation])
        let viewModel = makeViewModel(events: [
            .session(session), .retrieved([Self.citation]), .token("倍率"), .token("です [1]。"), .finished(answer),
        ])
        viewModel.input = "固有値とは？"

        viewModel.send()
        #expect(viewModel.input.isEmpty)
        #expect(viewModel.isAnswering)
        await waitUntilIdle(viewModel)

        #expect(viewModel.messages.map(\.content) == ["固有値とは？", "倍率です [1]。"])
        #expect(viewModel.messages.last?.citations.first?.heading == "定義")
        #expect(viewModel.selectedSessionID == session.id)
        #expect(viewModel.inspectedCitations.map(\.path) == ["数学/固有値.md"])
        #expect(viewModel.status == nil)
    }

    @Test("失敗したらメッセージを出し、途中までの答えは残す")
    func failure() async {
        let viewModel = makeViewModel(events: [.token("途中")], failure: ChatError.model("メモリが足りません"))
        viewModel.input = "質問"

        viewModel.send()
        await waitUntilIdle(viewModel)

        #expect(viewModel.errorMessage == "メモリが足りません")
        #expect(viewModel.messages.map(\.content) == ["質問", "途中"])
    }

    @Test("空の質問は送れない")
    func cannotSendEmpty() {
        let viewModel = makeViewModel(events: [])
        viewModel.input = "  \n"

        #expect(!viewModel.canSend)
        viewModel.send()
        #expect(viewModel.messages.isEmpty)
    }

    @Test("使えないモデルを選んでいたら、使えるものに切り替える")
    func fallsBackToAvailableModel() async {
        let viewModel = makeViewModel(events: [])
        viewModel.selectedModelID = ChatModelOption.appleID

        await viewModel.loadModels()

        #expect(viewModel.selectedModelID == ChatModelOption.defaultMLXID)
        #expect(viewModel.models.first?.detail == "Apple Intelligence が有効になっていません")
    }
}

private struct AskStub: AskQuestionUseCase {
    let events: [AnswerEvent]
    let failure: (any Error)?

    func callAsFunction(
        _ question: String, in session: ChatSession?, model: String, settings: GenerationSettings
    ) -> AsyncThrowingStream<AnswerEvent, any Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish(throwing: failure)
        }
    }
}

private struct HistoryStub: ListChatSessionsUseCase, LoadChatMessagesUseCase, DeleteChatSessionUseCase,
    ObserveChatSessionsUseCase, ListChatModelsUseCase
{
    func callAsFunction() async throws(ChatError) -> [ChatSession] { [] }
    func callAsFunction(_ sessionID: UUID) async throws(ChatError) -> [ChatMessage] { [] }
    func callAsFunction(_ sessionID: UUID) async throws(ChatError) {}
    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func callAsFunction() async -> [ChatModelOption] {
        [
            ChatModelOption(
                id: ChatModelOption.appleID, name: "Apple", kind: .apple, isDownloaded: true,
                unavailableReason: "Apple Intelligence が有効になっていません"),
            ChatModelOption(id: ChatModelOption.defaultMLXID, name: "Qwen3", kind: .mlx, isDownloaded: false),
        ]
    }
}

private struct RebuildStub: RebuildKnowledgeUseCase, ObserveKnowledgeBuildUseCase {
    func callAsFunction() async throws(KnowledgeError) {}
    func callAsFunction() async -> AsyncStream<KnowledgeBuildStep?> { AsyncStream { $0.finish() } }
}
