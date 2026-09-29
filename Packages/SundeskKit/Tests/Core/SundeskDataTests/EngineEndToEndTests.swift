//
//  EngineEndToEndTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import SundeskEngineClient
import SundeskMarkdown
import Testing

/// 本物のエンジンと小さなモデルで、アプリの流れを端から端まで確かめる。`SUNDESK_INTEGRATION=1` のときだけ走る。
///
/// 使うモデル（Qwen3-0.6B の 4bit と ruri-v3-130m、合わせて約 0.9GB）は、手元になければ取り込む。
@Suite(
    "エンジンとの結合", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SUNDESK_INTEGRATION"] == "1"),
    .timeLimit(.minutes(20))
)
struct EngineEndToEndTests {
    private static let model = "mlx-community/Qwen3-0.6B-4bit"
    private static let sampleVault = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SampleVault", directoryHint: .isDirectory)

    /// テストの間で 1 つのエンジンを使い回す。
    private static let process: EngineProcess = {
        let configuration = EngineConfiguration(
            engineDirectory: EngineLocator.defaultEngineDirectory(),
            uvExecutable: EngineLocator.findUV() ?? URL(filePath: "/opt/homebrew/bin/uv"))
        return EngineProcess(configuration: { configuration })
    }()

    @Test("SampleVault から知識を作り、ノートを根拠に答える")
    func knowledgeAndRAG() async throws {
        let vault = FileSystemVaultRepository(root: { Self.sampleVault })
        let repository = SwiftDataKnowledgeRepository(modelContainer: try KnowledgeStore.makeContainer(url: nil))
        let engine = EngineKnowledgeGateway(process: Self.process)
        let builder = KnowledgeBuilder(
            vault: vault, markdown: SwiftMarkdownParser(), chunker: MarkdownChunker(), engine: engine,
            repository: repository)

        try await builder.rebuild()

        let graph = try await repository.graph()
        let chunks = try await repository.allChunks()
        print("知識: 概念 \(graph.concepts.count)、関係 \(graph.relations.count)、チャンク \(chunks.count)")
        print("重要な概念:", graph.concepts.sorted { $0.pagerank > $1.pagerank }.prefix(15).map(\.label))
        #expect(graph.concepts.count > 20)
        #expect(graph.concepts.contains { $0.label == "固有値" })
        #expect(Set(graph.relations.map(\.kind)).isSuperset(of: [.cooccurrence, .link]))

        let retrieve = RetrieveContextInteractor(repository: repository, engine: engine)
        let found = try await retrieve("固有値とは何ですか", limit: 5)
        print("検索:", found.map { "\($0.chunk.noteTitle) \($0.sources.map(\.rawValue).sorted())" })
        #expect(found.contains { $0.chunk.notePath.contains("固有値") })
        #expect(found.first?.sources.contains(.vector) == true || found.contains { $0.sources.contains(.vector) })

        let chat = SwiftDataChatRepository(modelContainer: try KnowledgeStore.makeContainer(url: nil))
        let ask = AskQuestionInteractor(
            retrieve: retrieve, languageModel: LanguageModelRouter(process: Self.process), repository: chat)
        var answer = ""
        var citations: [Citation] = []
        for try await event in ask(
            "固有値とは何ですか。一言で。", in: nil, model: Self.model, settings: GenerationSettings(maxTokens: 200))
        {
            switch event {
            case .token(let text): answer += text
            case .finished(let message): citations = message.citations
            default: break
            }
        }
        print("回答:", answer)
        print("出典:", citations.map { "[\($0.number)] \($0.noteTitle)\($0.isCited ? " ✓" : "")" })
        #expect(!answer.isEmpty)
        #expect(!citations.isEmpty)
    }

    @Test("実験室で覗く")
    func lab() async throws {
        let lab = EngineLabGateway(process: Self.process)
        let prompt = LabPrompt(model: Self.model, text: "日本の首都は", chatTemplate: false)

        let tokens = try await lab.tokenize(prompt)
        print("トークン:", tokens.map(\.text))
        #expect(!tokens.isEmpty)

        let next = try await lab.nextToken(prompt, topK: 5, temperature: 1)
        print("次のトークン:", next.tokens.map { "\($0.text) \(String(format: "%.2f", $0.probability))" })
        #expect(next.tokens.count == 5)

        let attention = try await lab.attention(prompt, layer: 3)
        #expect(attention.mean.count == attention.tokens.count)
        #expect(attention.headCount > 0)

        let lens = try await lab.logitLens(prompt, topK: 1)
        #expect(lens.layers.count == attention.layerCount)

        let activations = try await lab.activations(prompt)
        #expect(activations.norms.count == attention.layerCount)

        var generated = ""
        for try await event in lab.generate(
            prompt, settings: SamplingSettings(temperature: 0.7, maxTokens: 20, seed: 1), alternatives: 3, adapter: nil)
        {
            if case .token(let token) = event { generated += token.token.text }
        }
        print("生成:", generated)
        #expect(!generated.isEmpty)

        let vector = try await lab.steeringVector(
            model: Self.model, layer: 10, positive: ["嬉しい", "楽しい"], negative: ["悲しい", "つらい"])
        let comparison = try await lab.steer(
            prompt, vector: vector, strength: 2, settings: SamplingSettings(maxTokens: 20, seed: 1))
        print("steering:", comparison.baseline, "→", comparison.steered)
        #expect(vector.norm > 0)

        let local = try await lab.localModels()
        #expect(local.contains { $0.id == Self.model && $0.kind == .llm })
        try await lab.unload(nil)
    }

    @Test("工房で作り、評価で比べ、スクラッチで覗く")
    func forgeAndScratch() async throws {
        let forge = EngineForgeGateway(process: Self.process)
        let output = FileManager.default.temporaryDirectory.appending(path: "sundesk-forge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }

        var built: [String] = []
        for (name, job) in [
            ("3bit", ForgeJob.quantize(model: Self.model, method: .affine(bits: 3, groupSize: 64, mixed: nil), overrides: [])),
            ("sim6", .quantize(model: Self.model, method: .simulated(bits: 6), overrides: [])),
            ("pruned", .prune(model: Self.model, dropLayers: [20, 21], dropHeads: [AttentionHead(layer: 3, head: 1)])),
        ] {
            let path = output.appending(path: name).path
            for try await event in forge.run(job, texts: [], outputPath: path) {
                if case .done(let model) = event {
                    print("作った: \(name) \(model.sizeBytes ?? 0) バイト、\(model.bitsPerWeight ?? 0) ビット/重み")
                    built.append(model.path)
                }
            }
        }
        #expect(built.count == 3)

        let texts = ["固有値とは、行列を掛けても向きが変わらないベクトルの倍率である。量子力学では、測定で得られる値が固有値になる。"]
        var results: [EvaluationResult] = []
        for try await event in forge.evaluate(
            ([Self.model] + built).map { EvaluationTarget(model: $0) }, texts: texts, prompts: ["日本の首都は"],
            maxTokens: 16, seed: 0)
        {
            if case .result(let result) = event { results.append(result) }
        }
        for result in results {
            print("評価: \((result.target.model as NSString).lastPathComponent) PPL \(result.perplexity)、\(result.samples.first ?? "")")
        }
        #expect(results.count == 4)

        var outputs: [ScratchOutput] = []
        for try await output in forge.run(
            session: "test", code: "x = model.args.num_hidden_layers\nprint(x)\nshow([{\"層\": 0, \"値\": 1.5}])\nx * 2",
            model: Self.model, adapter: nil)
        {
            outputs.append(output)
        }
        print("スクラッチ:", outputs.map { "\($0)".prefix(60) })
        #expect(outputs.contains(.stdout("28\n")))
        #expect(outputs.contains(.value("56")))
        #expect(outputs.contains { if case .table = $0 { true } else { false } })
        try await forge.reset(session: "test")
    }
}
