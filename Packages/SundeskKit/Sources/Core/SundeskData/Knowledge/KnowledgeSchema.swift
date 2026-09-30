//
//  KnowledgeSchema.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SwiftData

/// 知識（チャンク、埋め込み、知識グラフ）と、それを使った会話のスキーマ。Vault ごとに別のファイルに置く。
///
/// 知識グラフの線は、リレーションでたどらず、整数の ID だけの表にする（計算するときにメモリへ展開する）。
public enum KnowledgeSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ChunkRecord.self, ConceptRecord.self, RelationRecord.self, MentionRecord.self,
            ChatSessionRecord.self, ChatMessageRecord.self,
        ]
    }

    @Model
    public final class ChunkRecord {
        #Unique<ChunkRecord>([\.chunkID])
        #Index<ChunkRecord>([\.chunkID], [\.notePath])

        public var chunkID: String
        public var notePath: String
        public var noteTitle: String
        public var headingPath: [String]
        public var text: String
        public var plainText: String
        public var line: Int
        public var ordinal: Int
        public var contentHash: String
        /// 埋め込み（Float32 の並び）。
        @Attribute(.externalStorage) public var embedding: Data?
        public var embeddingModel: String?

        public init(
            chunkID: String, notePath: String, noteTitle: String, headingPath: [String], text: String,
            plainText: String, line: Int, ordinal: Int, contentHash: String, embedding: Data?, embeddingModel: String?
        ) {
            self.chunkID = chunkID
            self.notePath = notePath
            self.noteTitle = noteTitle
            self.headingPath = headingPath
            self.text = text
            self.plainText = plainText
            self.line = line
            self.ordinal = ordinal
            self.contentHash = contentHash
            self.embedding = embedding
            self.embeddingModel = embeddingModel
        }
    }

    @Model
    public final class ConceptRecord {
        #Unique<ConceptRecord>([\.conceptID])

        public var conceptID: Int
        public var label: String
        public var normalized: String
        public var score: Double
        public var frequency: Int
        public var pagerank: Double
        public var community: Int

        public init(
            conceptID: Int, label: String, normalized: String, score: Double, frequency: Int, pagerank: Double,
            community: Int
        ) {
            self.conceptID = conceptID
            self.label = label
            self.normalized = normalized
            self.score = score
            self.frequency = frequency
            self.pagerank = pagerank
            self.community = community
        }
    }

    @Model
    public final class RelationRecord {
        public var source: Int
        public var target: Int
        public var kind: String
        public var weight: Double
        public var evidence: String?

        public init(source: Int, target: Int, kind: String, weight: Double, evidence: String?) {
            self.source = source
            self.target = target
            self.kind = kind
            self.weight = weight
            self.evidence = evidence
        }
    }

    @Model
    public final class MentionRecord {
        #Index<MentionRecord>([\.concept], [\.chunk])

        public var concept: Int
        public var chunk: String
        public var count: Int

        public init(concept: Int, chunk: String, count: Int) {
            self.concept = concept
            self.chunk = chunk
            self.count = count
        }
    }

    /// RAG の会話。あとから見返せるように残す。
    @Model
    public final class ChatSessionRecord {
        #Unique<ChatSessionRecord>([\.sessionID])

        public var sessionID: UUID
        public var title: String
        public var model: String
        public var createdAt: Date
        public var updatedAt: Date

        public init(sessionID: UUID, title: String, model: String, createdAt: Date, updatedAt: Date) {
            self.sessionID = sessionID
            self.title = title
            self.model = model
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class ChatMessageRecord {
        #Index<ChatMessageRecord>([\.sessionID])

        public var messageID: UUID
        public var sessionID: UUID
        public var role: String
        public var content: String
        /// 出典（JSON）。
        public var citations: Data
        public var createdAt: Date

        public init(messageID: UUID, sessionID: UUID, role: String, content: String, citations: Data, createdAt: Date) {
            self.messageID = messageID
            self.sessionID = sessionID
            self.role = role
            self.content = content
            self.citations = citations
            self.createdAt = createdAt
        }
    }
}

public enum KnowledgeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [KnowledgeSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

typealias ChunkRecord = KnowledgeSchemaV1.ChunkRecord
typealias ConceptRecord = KnowledgeSchemaV1.ConceptRecord
typealias RelationRecord = KnowledgeSchemaV1.RelationRecord
typealias MentionRecord = KnowledgeSchemaV1.MentionRecord
typealias ChatSessionRecord = KnowledgeSchemaV1.ChatSessionRecord
typealias ChatMessageRecord = KnowledgeSchemaV1.ChatMessageRecord

/// 知識の保存先を作る。
public enum KnowledgeStore {
    /// - Parameter url: 保存するファイル。nil ならメモリの上だけに置く（テスト用）。
    public static func makeContainer(url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: KnowledgeSchemaV1.self)
        let configuration =
            if let url {
                ModelConfiguration(schema: schema, url: url)
            } else {
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
        return try ModelContainer(
            for: schema, migrationPlan: KnowledgeMigrationPlan.self, configurations: configuration)
    }

    /// Vault ごとに別のファイルにする。
    public static func defaultURL(forVault vault: URL) throws -> URL {
        try NoteIndexStore.defaultURL(forVault: vault, folder: "Knowledge")
    }
}
