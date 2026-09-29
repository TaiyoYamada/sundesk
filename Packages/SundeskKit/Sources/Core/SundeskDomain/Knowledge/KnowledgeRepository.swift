//
//  KnowledgeRepository.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// ノートを見出しで区切る。実装は Infrastructure 層（SundeskMarkdown）にある。
public protocol NoteChunking: Sendable {
    func chunks(for source: String, path: String, title: String) -> [NoteChunk]
}

/// PDF などの文書から、ページごとの文字を取り出す。実装は Data 層（PDFKit）にある。
public protocol DocumentTextExtracting: Sendable {
    func pages(of url: URL) -> [String]
}

/// 埋め込みの種類（質問か、検索される文書か）。
public enum EmbeddingKind: String, Sendable {
    case query
    case document
}

/// 埋め込みの結果。
public struct EmbeddingBatch: Sendable, Equatable {
    public let model: String
    public let vectors: [[Float]]

    public init(model: String, vectors: [[Float]]) {
        self.model = model
        self.vectors = vectors
    }
}

/// 知識グラフの材料にするノート。
public struct GraphSourceNote: Sendable, Equatable {
    public let path: String
    public let title: String
    /// 解決済みのリンク先のパス。
    public let links: [String]
    public let chunks: [NoteChunk]

    public init(path: String, title: String, links: [String], chunks: [NoteChunk]) {
        self.path = path
        self.title = title
        self.links = links
        self.chunks = chunks
    }
}

/// 知識の計算（埋め込み、グラフ）。実装は Python のエンジンを呼ぶ。
public protocol KnowledgeEngine: Sendable {
    func embed(_ texts: [String], kind: EmbeddingKind) async throws(KnowledgeError) -> EmbeddingBatch
    func buildGraph(notes: [GraphSourceNote], similarity: Bool) async throws(KnowledgeError) -> KnowledgeGraph
}

/// 埋め込みを付けたチャンク（保存するとき）。
public struct EmbeddedChunk: Sendable, Equatable {
    public let chunk: NoteChunk
    /// 本文のハッシュ。変わっていなければ、前回の埋め込みを使い回す。
    public let contentHash: String
    public let embedding: [Float]?

    public init(chunk: NoteChunk, contentHash: String, embedding: [Float]?) {
        self.chunk = chunk
        self.contentHash = contentHash
        self.embedding = embedding
    }
}

/// 似たチャンク（ベクトル検索の結果）。
public struct ScoredChunk: Sendable, Equatable {
    public let chunkID: String
    public let score: Double

    public init(chunkID: String, score: Double) {
        self.chunkID = chunkID
        self.score = score
    }
}

/// 知識（チャンク、埋め込み、知識グラフ）を保存する。Vault ごとに持つ。
public protocol KnowledgeRepository: Sendable {
    /// 全部を入れ替える（知識は毎回作り直す）。
    func replace(chunks: [EmbeddedChunk], graph: KnowledgeGraph, embeddingModel: String?) async throws(KnowledgeError)
    func graph() async throws(KnowledgeError) -> KnowledgeGraph
    func allChunks() async throws(KnowledgeError) -> [NoteChunk]
    func chunks(ids: [String]) async throws(KnowledgeError) -> [NoteChunk]
    /// 保存済みの埋め込み（本文のハッシュ → ベクトル）。作り直すときに使い回す。
    func storedEmbeddings(model: String) async throws(KnowledgeError) -> [String: [Float]]
    /// 質問のベクトルに近いチャンク（内積の大きい順）。
    func nearestChunks(to vector: [Float], limit: Int) async throws(KnowledgeError) -> [ScoredChunk]
    /// 知識が入れ替わるたびに流れる。
    func changes() -> AsyncStream<Void>
}
