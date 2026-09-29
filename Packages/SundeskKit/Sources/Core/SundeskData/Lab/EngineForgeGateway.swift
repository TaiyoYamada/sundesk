//
//  EngineForgeGateway.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SundeskEngineClient

/// モデルを作る・比べる計算と、Python のスクラッチを、エンジンに頼む（docs/engine-api.md のフェーズ 7）。
public struct EngineForgeGateway: ForgeEngine, ScratchEngine {
    private let process: EngineProcess

    public init(process: EngineProcess) {
        self.process = process
    }

    // MARK: - 作る

    public func run(_ job: ForgeJob, texts: [String], outputPath: String) -> AsyncThrowingStream<ForgeEvent, any Error>
    {
        let request = Self.request(for: job, texts: texts, outputPath: outputPath)
        let name = (outputPath as NSString).lastPathComponent
        return stream(request.path, body: request.body, as: ForgeLine.self, ensuring: request.models) { line in
            switch line.type {
            case "loading":
                return .loading(model: line.model ?? "")
            case "progress":
                if let iteration = line.iteration {
                    return .training(
                        iteration: iteration, total: line.total ?? 0, loss: line.loss ?? 0,
                        divergence: line.divergence, crossEntropy: line.crossEntropy)
                }
                return .progress(stage: line.stage ?? "", fraction: line.fraction, message: line.message)
            case "validation":
                return .validation(iteration: line.iteration ?? 0, loss: line.loss ?? 0)
            case "done":
                return .done(
                    ForgedModel(
                        name: name, path: line.outputDir ?? outputPath,
                        kind: line.kind == "adapter" ? .adapter : .model, sizeBytes: line.sizeBytes,
                        bitsPerWeight: line.bitsPerWeight))
            default:
                return nil
            }
        }
    }

    /// 仕事を、エンジンに送る要求にする。
    private struct ForgeRequest {
        let path: String
        let body: ForgeBody
        /// 先に取り込んでおくモデル。
        let models: [String]
    }

    private static func request(for job: ForgeJob, texts: [String], outputPath: String) -> ForgeRequest {
        switch job {
        case .quantize(let model, let method, let overrides):
            return ForgeRequest(
                path: "forge/quantize", body: .quantize(quantizeBody(model, method, overrides, outputPath)),
                models: [model])
        case .convert(let model, let dtype, let bits):
            let body = ConvertBody(
                model: model, outputDir: outputPath, dtype: dtype, quantize: bits.map { .init(bits: $0, groupSize: 64) }
            )
            return ForgeRequest(path: "forge/convert", body: .convert(body), models: [model])
        case .fuse(let model, let adapter, let dequantize):
            let body = FuseBody(model: model, adapter: adapter, outputDir: outputPath, dequantize: dequantize)
            return ForgeRequest(path: "forge/fuse", body: .fuse(body), models: [model])
        case .merge(let first, let second, let method, let ratio):
            let body = MergeBody(models: [first, second], outputDir: outputPath, method: method.rawValue, ratio: ratio)
            return ForgeRequest(path: "forge/merge", body: .merge(body), models: [first, second])
        case .prune(let model, let layers, let heads):
            let body = PruneBody(
                model: model, outputDir: outputPath, dropLayers: layers,
                dropHeads: heads.map { .init(layer: $0.layer, head: $0.head) })
            return ForgeRequest(path: "forge/prune", body: .prune(body), models: [model])
        case .distill(let teacher, let student, _, let settings):
            let body = DistillBody(
                teacher: teacher, student: student, texts: texts, outputDir: outputPath,
                iterations: settings.iterations, learningRate: settings.learningRate,
                temperature: settings.temperature, alpha: settings.alpha, maxSeqLength: settings.maxSequenceLength,
                batchSize: 1, loraRank: settings.loraRank)
            return ForgeRequest(path: "forge/distill", body: .distill(body), models: [teacher, student])
        }
    }

    private static func quantizeBody(
        _ model: String, _ method: QuantizationMethod, _ overrides: [QuantizationOverride], _ outputPath: String
    ) -> QuantizeBody {
        let overrides = overrides.map { QuantizeOverride(pattern: $0.pattern, bits: $0.bits) }
        switch method {
        case .affine(let bits, let groupSize, let mixed):
            return QuantizeBody(
                model: model, outputDir: outputPath, method: "affine", bits: bits, groupSize: groupSize, mixed: mixed,
                overrides: overrides, ternary: false)
        case .simulated(let bits):
            return QuantizeBody(
                model: model, outputDir: outputPath, method: "simulated", bits: bits, groupSize: 64, mixed: nil,
                overrides: overrides, ternary: false)
        case .ternary:
            return QuantizeBody(
                model: model, outputDir: outputPath, method: "simulated", bits: 2, groupSize: 64, mixed: nil,
                overrides: overrides, ternary: true)
        }
    }

    // MARK: - 比べる

    public func evaluate(
        _ targets: [EvaluationTarget], texts: [String], prompts: [String], maxTokens: Int, seed: Int
    ) -> AsyncThrowingStream<EvaluationEvent, any Error> {
        let body = EvaluateBody(
            models: targets.map { .init(model: $0.model, adapter: $0.adapter) }, texts: texts, prompts: prompts,
            maxTokens: maxTokens, seed: seed)
        return stream("forge/evaluate", body: body, as: EvaluateLine.self, ensuring: targets.map(\.model)) { line in
            switch line.type {
            case "loading":
                return .loading(model: line.model ?? "")
            case "result":
                return .result(
                    EvaluationResult(
                        target: EvaluationTarget(model: line.model ?? "", adapter: line.adapter),
                        perplexity: line.perplexity ?? .nan, tokens: line.tokens ?? 0, seconds: line.seconds ?? 0,
                        tokensPerSecond: line.tokensPerSecond ?? 0, sizeBytes: line.sizeBytes,
                        peakMemoryBytes: line.peakMemoryBytes, samples: line.samples ?? []))
            default:
                return nil
            }
        }
    }

    // MARK: - 書く

    public func run(
        session: String, code: String, model: String?, adapter: String?
    ) -> AsyncThrowingStream<ScratchOutput, any Error> {
        let body = ScratchBody(session: session, code: code, model: model, adapter: adapter)
        return stream(
            "scratch/run", body: body, as: ScratchLine.self, ensuring: model.map { [$0] } ?? [], passesErrorLines: true
        ) { line in
            switch line.type {
            case "stdout": .stdout(line.text ?? "")
            case "stderr": .stderr(line.text ?? "")
            case "image": line.pngBase64.flatMap { Data(base64Encoded: $0) }.map(ScratchOutput.image)
            case "table": .table(columns: line.columns ?? [], rows: (line.rows ?? []).map { $0.map(\.text) })
            case "value": .value(line.repr ?? "")
            case "done": .done(seconds: line.seconds ?? 0)
            case "error": .error(message: line.message ?? "失敗しました", traceback: line.traceback)
            default: nil
            }
        }
    }

    public func reset(session: String) async throws(LabError) {
        do {
            let client = try await process.runningClient()
            _ = try await client.post("scratch/reset", body: ResetBody(session: session), as: ResetResponse.self)
        } catch let error as EngineProcessError {
            throw .engine(EngineMapper.failure(from: error).message)
        } catch let error as EngineClientError {
            throw .engine(error.message)
        } catch {
            throw .engine(error.localizedDescription)
        }
    }

    // MARK: - 内部

    private func stream<Body: Encodable & Sendable, Line: Decodable & Sendable, Event: Sendable>(
        _ path: String, body: Body, as type: Line.Type, ensuring models: [String], passesErrorLines: Bool = false,
        map: @escaping @Sendable (Line) -> Event?
    ) -> AsyncThrowingStream<Event, any Error> {
        let process = process
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let client: EngineClient
                    do {
                        client = try await process.runningClient()
                    } catch let error as EngineProcessError {
                        throw LabError.engine(EngineMapper.failure(from: error).message)
                    }
                    for model in models {
                        try await EngineModelEnsurer.shared.ensure(model, client: client)
                    }
                    for try await line in client.stream(
                        path, body: body, as: Line.self, passesErrorLines: passesErrorLines)
                    {
                        if let event = map(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch let error as EngineClientError {
                    continuation.finish(throwing: LabError.engine(error.message))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// スクリプトを、アプリのデータフォルダの `Scripts/*.py` に置く。
public struct FileSystemScriptRepository: ScriptRepository {
    private let directory: @Sendable () -> URL?

    public init(directory: @escaping @Sendable () -> URL? = { try? AppDataDirectory.url("Scripts") }) {
        self.directory = directory
    }

    public func scripts() async throws(LabError) -> [Script] {
        guard let directory = directory() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "py" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map {
                    Script(name: url.deletingPathExtension().lastPathComponent, code: $0)
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func save(_ script: Script) async throws(LabError) {
        guard let url = file(named: script.name) else { throw .storage("スクリプトの置き場所を作れません") }
        do {
            try Data(script.code.utf8).write(to: url, options: .atomic)
        } catch {
            throw .storage(error.localizedDescription)
        }
    }

    public func delete(named name: String) async throws(LabError) {
        guard let url = file(named: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func file(named name: String) -> URL? {
        let safe = name.replacing(/[\/:\\]/, with: "-")
        return directory()?.appending(path: "\(safe).py")
    }
}
