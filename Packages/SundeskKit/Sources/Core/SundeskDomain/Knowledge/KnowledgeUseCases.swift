//
//  KnowledgeUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - 作り直す

public protocol RebuildKnowledgeUseCase: Sendable {
    /// ノートから、チャンク、埋め込み、知識グラフを作り直す。すでに作り直している途中なら、それを待つ。
    func callAsFunction() async throws(KnowledgeError)
}

public protocol ObserveKnowledgeBuildUseCase: Sendable {
    /// 作り直しの進み具合。今の状態を最初に流す（作り直していなければ nil）。
    func callAsFunction() async -> AsyncStream<KnowledgeBuildStep?>
}

public struct RebuildKnowledgeInteractor: RebuildKnowledgeUseCase {
    private let builder: KnowledgeBuilder

    public init(builder: KnowledgeBuilder) {
        self.builder = builder
    }

    public func callAsFunction() async throws(KnowledgeError) {
        try await builder.rebuild()
    }
}

public struct ObserveKnowledgeBuildInteractor: ObserveKnowledgeBuildUseCase {
    private let builder: KnowledgeBuilder

    public init(builder: KnowledgeBuilder) {
        self.builder = builder
    }

    public func callAsFunction() async -> AsyncStream<KnowledgeBuildStep?> {
        await builder.progress()
    }
}

/// 知識の作り直しを受け持つ。アプリに 1 つだけ置き、同時に 2 つ走らないようにする。
public actor KnowledgeBuilder {
    private let vault: any VaultRepository
    private let markdown: any MarkdownParsing
    private let chunker: any NoteChunking
    private let engine: any KnowledgeEngine
    private let repository: any KnowledgeRepository
    private let documents: (any DocumentTextExtracting)?
    private let batchSize: Int

    private var running: Task<Void, any Error>?
    private var step: KnowledgeBuildStep? {
        didSet { for observer in observers.values { observer.yield(step) } }
    }
    private var observers: [UUID: AsyncStream<KnowledgeBuildStep?>.Continuation] = [:]

    public init(
        vault: any VaultRepository,
        markdown: any MarkdownParsing,
        chunker: any NoteChunking,
        engine: any KnowledgeEngine,
        repository: any KnowledgeRepository,
        documents: (any DocumentTextExtracting)? = nil,
        batchSize: Int = 32
    ) {
        self.vault = vault
        self.markdown = markdown
        self.chunker = chunker
        self.engine = engine
        self.repository = repository
        self.documents = documents
        self.batchSize = batchSize
    }

    /// ノートから、チャンク、埋め込み、知識グラフを作り直す。すでに作り直している途中なら、それを待つ。
    public func rebuild() async throws(KnowledgeError) {
        let task: Task<Void, any Error>
        if let running {
            task = running
        } else {
            task = Task { try await self.build() }
            running = task
        }
        defer { if running == task { running = nil } }
        do {
            try await task.value
        } catch let error as KnowledgeError {
            throw error
        } catch {
            throw .engine(String(describing: error))
        }
    }

    /// 作り直しの進み具合。今の状態を最初に流す（作り直していなければ nil）。
    public func progress() -> AsyncStream<KnowledgeBuildStep?> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: KnowledgeBuildStep?.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.yield(step)
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func build() async throws(KnowledgeError) {
        do {
            try await buildSteps()
        } catch {
            step = nil
            throw error
        }
    }

    private func buildSteps() async throws(KnowledgeError) {
        // 1. ノートを読んで区切る
        let tree: VaultNode
        do {
            tree = try await vault.loadTree()
        } catch {
            throw .vault(error)
        }
        let files = tree.files
        let titles = await FolderNote.titles(in: files.map(\.path), vault: vault, markdown: markdown)
        let resolver = LinkResolver(paths: files.map(\.path), titles: titles)
        let notesToRead = files.filter { $0.kind == .markdown }
        var notes: [GraphSourceNote] = []
        for (index, file) in notesToRead.enumerated() {
            step = .readingNotes(done: index, total: notesToRead.count)
            guard let source = try? await vault.readText(at: file.path) else { continue }
            let analysis = markdown.analyze(source, path: file.path)
            let title = analysis.title ?? String(file.name.split(separator: ".").first ?? Substring(file.name))
            let links = analysis.links.compactMap { resolver.resolve($0.target, exact: $0.isExactPath) }
            let chunks = chunker.chunks(for: source, path: file.path, title: title)
            notes.append(
                GraphSourceNote(path: file.path, title: title, links: Array(Set(links)).sorted(), chunks: chunks))
        }

        // 論文の PDF の本文も、検索と出典に使う（知識グラフには入れない。英文が多く、概念がそちらに偏るため）
        let pdfChunks = paperChunks(files: files, notes: notes)

        // 2. 埋め込み（変わっていないチャンクは前回のものを使う）
        let chunks = notes.flatMap(\.chunks) + pdfChunks
        let hashes = chunks.map { Self.hash($0.text) }
        var model: String?
        var stored: [String: [Float]] = [:]
        var embeddings: [String: [Float]] = [:]
        let firstBatch = try await engine.embed(["確認"], kind: .query)
        model = firstBatch.model
        stored = try await repository.storedEmbeddings(model: firstBatch.model)
        let missing = zip(chunks, hashes).filter { stored[$0.1] == nil }
        for start in stride(from: 0, to: missing.count, by: batchSize) {
            step = .embedding(done: start, total: missing.count)
            let batch = Array(missing[start..<min(start + batchSize, missing.count)])
            let result = try await engine.embed(batch.map { Self.embeddingText(for: $0.0) }, kind: .document)
            for ((_, hash), vector) in zip(batch, result.vectors) {
                embeddings[hash] = vector
            }
        }
        embeddings.merge(stored) { new, _ in new }

        // 3. 知識グラフ
        step = .buildingGraph
        let graph = try await engine.buildGraph(notes: notes, similarity: true)

        // 4. 保存
        step = .saving
        let embedded = zip(chunks, hashes).map { chunk, hash in
            EmbeddedChunk(chunk: chunk, contentHash: hash, embedding: embeddings[hash])
        }
        try await repository.replace(chunks: embedded, graph: graph, embeddingModel: model)
        step = .finished(concepts: graph.concepts.count, relations: graph.relations.count, chunks: chunks.count)
    }

    /// 論文のフォルダ（`Papers/<キー>/`）の PDF を、ページごとに区切る。題名は論文メモから取る。
    private func paperChunks(files: [VaultNode], notes: [GraphSourceNote]) -> [NoteChunk] {
        guard let documents else { return [] }
        let titles = Dictionary(notes.map { ($0.path, $0.title) }, uniquingKeysWith: { first, _ in first })
        var chunks: [NoteChunk] = []
        for file in files where file.kind == .pdf && file.path.hasPrefix("Papers/") {
            let folder = (file.path as NSString).deletingLastPathComponent
            let title = titles["\(folder)/note.md"] ?? file.name
            for (index, page) in documents.pages(of: vault.fileURL(for: file.path)).enumerated() {
                let text = page.replacing(/[ \t]+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count > 40 else { continue }
                for piece in Self.pieces(of: text, maxLength: 1200) {
                    chunks.append(
                        NoteChunk(
                            id: "\(file.path)#\(chunks.count)", notePath: file.path, noteTitle: title,
                            headingPath: [title, "p.\(index + 1)"], text: piece, plainText: piece, line: index + 1))
                }
            }
        }
        return chunks
    }

    /// 長い文字を、段落の切れ目でおよそ `maxLength` 文字ずつに分ける。
    static func pieces(of text: String, maxLength: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if current.count + paragraph.count > maxLength, !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + paragraph
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// 埋め込む文字列。見出しの階層を前に付けて、どの節の話かを分かるようにする。
    static func embeddingText(for chunk: NoteChunk) -> String {
        (chunk.headingPath.joined(separator: " > ") + "\n" + chunk.text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 本文のハッシュ（FNV-1a の 64 ビット。変わったかどうかを見分けるだけなので、暗号の強さは要らない）。
    static func hash(_ text: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16) + "-" + String(text.utf8.count)
    }
}

// MARK: - 読む

public protocol LoadKnowledgeGraphUseCase: Sendable {
    func callAsFunction() async throws(KnowledgeError) -> KnowledgeGraph
}

public struct LoadKnowledgeGraphInteractor: LoadKnowledgeGraphUseCase {
    private let repository: any KnowledgeRepository

    public init(repository: any KnowledgeRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws(KnowledgeError) -> KnowledgeGraph {
        try await repository.graph()
    }
}

public protocol ObserveKnowledgeUseCase: Sendable {
    func callAsFunction() -> AsyncStream<Void>
}

public struct ObserveKnowledgeInteractor: ObserveKnowledgeUseCase {
    private let repository: any KnowledgeRepository

    public init(repository: any KnowledgeRepository) {
        self.repository = repository
    }

    public func callAsFunction() -> AsyncStream<Void> {
        repository.changes()
    }
}

/// 概念が出てくるノートの節（出現の多い順）。
public protocol FindConceptSourcesUseCase: Sendable {
    func callAsFunction(concept: Int, in graph: KnowledgeGraph) async throws(KnowledgeError) -> [ConceptSource]
}

public struct FindConceptSourcesInteractor: FindConceptSourcesUseCase {
    private let repository: any KnowledgeRepository

    public init(repository: any KnowledgeRepository) {
        self.repository = repository
    }

    public func callAsFunction(concept: Int, in graph: KnowledgeGraph) async throws(KnowledgeError) -> [ConceptSource] {
        let mentions = graph.mentions.filter { $0.concept == concept }.sorted { $0.count > $1.count }
        let chunks = try await repository.chunks(ids: mentions.map(\.chunk))
        let byID = Dictionary(chunks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return mentions.compactMap { mention in
            byID[mention.chunk].map { ConceptSource(chunk: $0, count: mention.count) }
        }
    }
}
