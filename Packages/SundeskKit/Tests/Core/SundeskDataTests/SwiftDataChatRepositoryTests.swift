//
//  SwiftDataChatRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import Testing

@Suite("SwiftDataChatRepository")
struct SwiftDataChatRepositoryTests {
    private func makeRepository() throws -> SwiftDataChatRepository {
        SwiftDataChatRepository(modelContainer: try KnowledgeStore.makeContainer(url: nil))
    }

    @Test("会話を作り、発言を出典ごと保存して、読み戻せる")
    func roundTrip() async throws {
        let repository = try makeRepository()
        let session = try await repository.createSession(title: "固有値とは", model: "apple.foundation-models")
        let citation = Citation(
            number: 1, chunkID: "a#0", notePath: "a.md", noteTitle: "A", headingPath: ["A", "定義"], line: 3,
            snippet: "…", isCited: true)

        try await repository.append(ChatMessage(role: .user, content: "固有値とは？"), to: session.id)
        try await repository.append(
            ChatMessage(
                role: .assistant, content: "倍率 [1]", citations: [citation], createdAt: .now.addingTimeInterval(1)),
            to: session.id)

        let messages = try await repository.messages(in: session.id)
        #expect(messages.map(\.role) == [.user, .assistant])
        #expect(messages.last?.citations == [citation])
        #expect(try await repository.sessions().map(\.title) == ["固有値とは"])
    }

    @Test("新しく話した会話を先に並べ、消した会話は発言ごと消える")
    func orderingAndDeletion() async throws {
        let repository = try makeRepository()
        let first = try await repository.createSession(title: "1", model: "m")
        let second = try await repository.createSession(title: "2", model: "m")
        try await repository.append(
            ChatMessage(role: .user, content: "x", createdAt: .now.addingTimeInterval(60)), to: first.id)

        #expect(try await repository.sessions().map(\.title) == ["1", "2"])

        try await repository.deleteSession(first.id)
        #expect(try await repository.sessions().map(\.id) == [second.id])
        #expect(try await repository.messages(in: first.id).isEmpty)
    }
}
