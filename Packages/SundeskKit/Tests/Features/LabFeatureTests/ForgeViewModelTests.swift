//
//  ForgeViewModelTests.swift
//  LabFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import LabFeature
import SundeskDomain
import Testing

@MainActor
@Suite("ForgeViewModel と ScratchViewModel")
struct ForgeViewModelTests {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("量子化の設定と上書きを、仕事に直して送る")
    func quantizeJob() async {
        let forge = ForgeStub()
        let viewModel = ForgeViewModel(
            forge: forge, modelManagement: ModelsStub(), records: LabStub(failure: nil), loadVaultTree: TreeStub())
        await viewModel.load()
        viewModel.quantizeModel = "mlx-community/Qwen3-0.6B-4bit"
        viewModel.quantizeMethod = .simulated
        viewModel.quantizeBits = 7
        viewModel.quantizeOverrides = "lm_head=8\nembed_tokens="

        viewModel.quantize()
        await waitUntil { !viewModel.isRunning }

        #expect(
            forge.jobs.value.first
                == .quantize(
                    model: "mlx-community/Qwen3-0.6B-4bit", method: .simulated(bits: 7),
                    overrides: [.init(pattern: "lm_head", bits: 8), .init(pattern: "embed_tokens", bits: nil)]))
        #expect(forge.names.value.first == "Qwen3-0.6B-sim7bit")
        #expect(viewModel.lastOutput?.detail == "モデル・1 KB・3.50 ビット/重み")
    }

    @Test("枝刈りの層とヘッドを読み取る。空なら断る")
    func pruneJob() async {
        let forge = ForgeStub()
        let viewModel = ForgeViewModel(
            forge: forge, modelManagement: ModelsStub(), records: LabStub(failure: nil), loadVaultTree: TreeStub())
        viewModel.pruneModel = "m"

        viewModel.prune()
        #expect(viewModel.errorMessage == "取り除く層かヘッドを入れてください")

        viewModel.pruneLayers = "20, 21"
        viewModel.pruneHeads = "3.5"
        viewModel.prune()
        await waitUntil { !viewModel.isRunning }
        #expect(
            forge.jobs.value.first == .prune(model: "m", dropLayers: [20, 21], dropHeads: [.init(layer: 3, head: 5)]))
    }

    @Test("スクラッチの出力をまとめ、エラーは traceback つきで出す")
    func scratchOutputs() async {
        let viewModel = ScratchViewModel(scratch: ScratchStub(), modelManagement: ModelsStub())

        viewModel.run()
        await waitUntil { !viewModel.isRunning }

        let kinds = viewModel.outputs.map(\.kind)
        #expect(kinds.count == 4)
        #expect(kinds[1] == .text("1\n2\n", isError: false))
        #expect(kinds[2] == .table(columns: ["層"], rows: [["0"]]))
        #expect(kinds[3] == .error(message: "NameError: x", traceback: "Traceback…"))
    }
}

nonisolated private final class Recorder<Value>: @unchecked Sendable {
    var value: [Value] = []
}

private struct ForgeStub: ForgeUseCases {
    let jobs = Recorder<ForgeJob>()
    let names = Recorder<String>()

    func callAsFunction(_ job: ForgeJob, name: String) -> AsyncThrowingStream<ForgeEvent, any Error> {
        jobs.value.append(job)
        names.value.append(name)
        return AsyncThrowingStream { continuation in
            continuation.yield(
                .done(
                    ForgedModel(name: name, path: "/Models/\(name)", kind: .model, sizeBytes: 1_000, bitsPerWeight: 3.5)
                ))
            continuation.finish()
        }
    }

    func callAsFunction(
        _ targets: [EvaluationTarget], folder: String, prompts: [String], maxTokens: Int
    ) -> AsyncThrowingStream<EvaluationEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func callAsFunction(deleting path: String) {}
}

private struct ScratchStub: ScratchUseCase {
    func run(session: String, code: String, model: String?, adapter: String?) -> AsyncThrowingStream<
        ScratchOutput, any Error
    > {
        AsyncThrowingStream { continuation in
            continuation.yield(.stdout("1\n"))
            continuation.yield(.stdout("2\n"))
            continuation.yield(.table(columns: ["層"], rows: [["0"]]))
            continuation.yield(.error(message: "NameError: x", traceback: "Traceback…"))
            continuation.finish()
        }
    }

    func reset(session: String) async throws(LabError) {}
    func scripts() async throws(LabError) -> [Script] { [] }
    func save(_ script: Script) async throws(LabError) {}
    func delete(scriptNamed name: String) async throws(LabError) {}
}
