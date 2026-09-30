//
//  ForgeUseCaseTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Testing

@testable import SundeskDomain

@Suite("工房")
struct ForgeUseCaseTests {
    private let files: [String: String] = ["数学/a.md": "固有値の本文", "数学/b.md": "行列の本文", "Swift/c.md": "actor"]

    private func makeForge(engine: ForgeEngineSpy, records: LabRecordsSpy = LabRecordsSpy()) -> ForgeInteractor {
        ForgeInteractor(
            engine: engine, records: records, vault: VaultStub(files: files), markdown: MarkdownParserStub(),
            files: FilesStub())
    }

    @Test("量子化したモデルを、名前のフォルダに作って記録する")
    func quantizes() async throws {
        let engine = ForgeEngineSpy()
        let records = LabRecordsSpy()
        let forge = makeForge(engine: engine, records: records)

        for try await _ in forge(
            .quantize(model: "m", method: .affine(bits: 3, groupSize: 64, mixed: nil), overrides: []), name: "m-3bit")
        {}

        #expect(await engine.outputPaths == ["/models/m-3bit"])
        let experiment = try #require(await records.saved.first)
        #expect(experiment.kind == .forge)
        #expect(experiment.parameters["ビット"] == "3")
        #expect(experiment.summary.contains("量子化して「m-3bit」を作成"))
    }

    @Test("蒸留はフォルダのノートを渡し、LoRA ならアダプタとして記録する")
    func distills() async throws {
        let engine = ForgeEngineSpy(kind: .adapter)
        let records = LabRecordsSpy()
        let forge = makeForge(engine: engine, records: records)

        for try await _ in forge(
            .distill(teacher: "t", student: "s", folder: "数学", settings: DistillationSettings(loraRank: 8)), name: "蒸留")
        {}

        #expect(await engine.texts.sorted() == ["固有値の本文", "行列の本文"])
        #expect(await engine.outputPaths == ["/adapters/蒸留"])
        let adapter = try #require(await records.savedAdapters.first)
        #expect(adapter.model == "s")
        #expect(adapter.source.contains("t から蒸留"))
    }

    @Test("評価の結果を流し、まとめを記録する")
    func evaluates() async throws {
        let records = LabRecordsSpy()
        let forge = makeForge(engine: ForgeEngineSpy(), records: records)
        var results: [EvaluationResult] = []

        for try await event in forge(
            [EvaluationTarget(model: "a"), EvaluationTarget(model: "/x/b")], folder: "", prompts: ["p"], maxTokens: 8)
        {
            if case .result(let result) = event { results.append(result) }
        }

        #expect(results.map(\.target.model) == ["a", "/x/b"])
        #expect(await records.saved.first?.summary == "a: PPL 10.00、50 トークン/秒、b: PPL 10.00、50 トークン/秒")
    }

    @Test("作る仕事ごとに、記録に残す設定")
    func parameters() {
        #expect(ForgeJob.quantize(model: "m", method: .ternary, overrides: []).parameters == ["方式": "3 値（1.58 ビット）"])
        #expect(
            ForgeJob.prune(model: "m", dropLayers: [20, 21], dropHeads: [AttentionHead(layer: 3, head: 5)]).parameters
                == ["層": "20,21", "ヘッド": "3.5"])
    }

    @Test("工房で作ったモデルはフォルダを消し、キャッシュのモデルはエンジンで消す")
    func deletesModels() async throws {
        let files = FilesStub()
        let management = ModelManagementInteractor(repository: ModelRepositorySpy(), files: files)

        try await management.delete(["/Models/m-3bit"])

        #expect(files.removed.value == ["/Models/m-3bit"])
    }

    @Test("まとめて消すとき、1 つ失敗しても残りは消し、失敗を知らせる")
    func deletesModelsInBulk() async {
        let files = FilesStub()
        let management = ModelManagementInteractor(repository: ModelRepositorySpy(), files: files)

        await #expect(throws: LabError.engine("キャッシュのモデルを消そうとした")) {
            try await management.delete(["/Models/a", "mlx-community/x", "/Models/b"])
        }

        #expect(files.removed.value == ["/Models/a", "/Models/b"])
    }
}

actor ForgeEngineSpy: ForgeEngine {
    private(set) var outputPaths: [String] = []
    private(set) var texts: [String] = []
    private let kind: ForgedModel.Kind

    init(kind: ForgedModel.Kind = .model) {
        self.kind = kind
    }

    private func record(_ path: String, _ texts: [String]) {
        outputPaths.append(path)
        self.texts = texts
    }

    nonisolated func run(_ job: ForgeJob, texts: [String], outputPath: String) -> AsyncThrowingStream<
        ForgeEvent, any Error
    > {
        AsyncThrowingStream { continuation in
            Task {
                await self.record(outputPath, texts)
                continuation.yield(.progress(stage: "quantizing", fraction: 0.5, message: nil))
                continuation.yield(
                    .done(
                        ForgedModel(
                            name: (outputPath as NSString).lastPathComponent, path: outputPath, kind: kind,
                            sizeBytes: 1_000, bitsPerWeight: 3.5)))
                continuation.finish()
            }
        }
    }

    nonisolated func evaluate(
        _ targets: [EvaluationTarget], texts: [String], prompts: [String], maxTokens: Int, seed: Int
    ) -> AsyncThrowingStream<EvaluationEvent, any Error> {
        AsyncThrowingStream { continuation in
            for target in targets {
                continuation.yield(.loading(model: target.model))
                continuation.yield(
                    .result(
                        EvaluationResult(
                            target: target, perplexity: 10, tokens: 100, seconds: 2, tokensPerSecond: 50,
                            sizeBytes: nil, peakMemoryBytes: nil, samples: ["…"])))
            }
            continuation.finish()
        }
    }
}

struct ModelRepositorySpy: ModelRepository {
    func localModels() async throws(LabError) -> [LocalModel] { [] }
    func download(_ id: String) -> AsyncThrowingStream<DownloadEvent, any Error> { AsyncThrowingStream { $0.finish() } }
    func delete(_ id: String) async throws(LabError) { throw .engine("キャッシュのモデルを消そうとした") }
    func loadedModels() async throws(LabError) -> LoadedModels { .none }
    func unload(_ kind: ModelKind?) async throws(LabError) {}
}

@Suite("スクリプト")
struct ScratchInteractorTests {
    @Test("まとめて消し、名前は前後の空白を除いて変える")
    func deletesAndRenames() async throws {
        let scripts = ScriptRepositorySpy()
        let scratch = ScratchInteractor(engine: ScratchEngineStub(), scripts: scripts, records: LabRecordsSpy())

        try await scratch.delete(scriptsNamed: ["a", "b"])
        try await scratch.rename(scriptNamed: "c", to: " d ")
        try await scratch.rename(scriptNamed: "e", to: "e")
        await #expect(throws: LabError.self) { try await scratch.rename(scriptNamed: "c", to: "  ") }

        #expect(await scripts.deleted == ["a", "b"])
        #expect(await scripts.renamed == ["c→d"])
    }
}

actor ScriptRepositorySpy: ScriptRepository {
    private(set) var deleted: [String] = []
    private(set) var renamed: [String] = []

    func scripts() async throws(LabError) -> [Script] { [] }
    func save(_ script: Script) async throws(LabError) {}
    func delete(named name: String) async throws(LabError) { deleted.append(name) }
    func rename(named name: String, to newName: String) async throws(LabError) { renamed.append("\(name)→\(newName)") }
}

struct ScratchEngineStub: ScratchEngine {
    func run(
        session: String, code: String, model: String?, adapter: String?
    ) -> AsyncThrowingStream<ScratchOutput, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func reset(session: String) async throws(LabError) {}
}
