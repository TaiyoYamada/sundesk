//
//  SwiftDataChatRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SwiftData

/// 会話を SwiftData で持つ（知識と同じ保存先。Vault ごとに分かれる）。
public actor SwiftDataChatRepository: ChatRepository, ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    nonisolated private let broadcaster = ChangeBroadcaster()

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    public func sessions() async throws(ChatError) -> [ChatSession] {
        try storage {
            try modelContext.fetch(
                FetchDescriptor<ChatSessionRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )
            .map(Self.session)
        }
    }

    public func messages(in sessionID: UUID) async throws(ChatError) -> [ChatMessage] {
        try storage {
            try modelContext.fetch(
                FetchDescriptor<ChatMessageRecord>(
                    predicate: #Predicate { $0.sessionID == sessionID }, sortBy: [SortDescriptor(\.createdAt)])
            )
            .map { record in
                ChatMessage(
                    id: record.messageID, role: ChatRole(rawValue: record.role) ?? .user, content: record.content,
                    citations: (try? JSONDecoder().decode([Citation].self, from: record.citations)) ?? [],
                    createdAt: record.createdAt)
            }
        }
    }

    public func createSession(title: String, model: String) async throws(ChatError) -> ChatSession {
        let now = Date.now
        let session = ChatSession(id: UUID(), title: title, model: model, createdAt: now, updatedAt: now)
        try storage {
            modelContext.insert(
                ChatSessionRecord(sessionID: session.id, title: title, model: model, createdAt: now, updatedAt: now))
            try modelContext.save()
        }
        broadcaster.send()
        return session
    }

    public func append(_ message: ChatMessage, to sessionID: UUID) async throws(ChatError) {
        try storage {
            let citations = try JSONEncoder().encode(message.citations)
            modelContext.insert(
                ChatMessageRecord(
                    messageID: message.id, sessionID: sessionID, role: message.role.rawValue, content: message.content,
                    citations: citations, createdAt: message.createdAt))
            if let session = try fetchSession(sessionID) { session.updatedAt = message.createdAt }
            try modelContext.save()
        }
        broadcaster.send()
    }

    public func deleteSession(_ id: UUID) async throws(ChatError) {
        try storage {
            try modelContext.delete(model: ChatMessageRecord.self, where: #Predicate { $0.sessionID == id })
            try modelContext.delete(model: ChatSessionRecord.self, where: #Predicate { $0.sessionID == id })
            try modelContext.save()
        }
        broadcaster.send()
    }

    nonisolated public func changes() -> AsyncStream<Void> {
        broadcaster.subscribe()
    }

    private func fetchSession(_ id: UUID) throws -> ChatSessionRecord? {
        try modelContext.fetch(FetchDescriptor<ChatSessionRecord>(predicate: #Predicate { $0.sessionID == id })).first
    }

    private func storage<T>(_ body: () throws -> T) throws(ChatError) -> T {
        do {
            return try body()
        } catch {
            throw .storage(error.localizedDescription)
        }
    }

    private static func session(_ record: ChatSessionRecord) -> ChatSession {
        ChatSession(
            id: record.sessionID, title: record.title, model: record.model, createdAt: record.createdAt,
            updatedAt: record.updatedAt)
    }
}
