//
//  ForgeUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// モデルを作る・比べる計算（エンジン）。
public protocol ForgeEngine: Sendable {
    /// `texts` は蒸留に使う文章（蒸留のときだけ）。
    func run(_ job: ForgeJob, texts: [String], outputPath: String) -> AsyncThrowingStream<ForgeEvent, any Error>
    func evaluate(
        _ targets: [EvaluationTarget], texts: [String], prompts: [String], maxTokens: Int, seed: Int
    ) -> AsyncThrowingStream<EvaluationEvent, any Error>
}

/// エンジンの中で Python を動かす。
public protocol ScratchEngine: Sendable {
    func run(
        session: String, code: String, model: String?, adapter: String?
    ) -> AsyncThrowingStream<ScratchOutput, any Error>
    func reset(session: String) async throws(LabError)
}

/// 保存したスクリプト。
public protocol ScriptRepository: Sendable {
    func scripts() async throws(LabError) -> [Script]
    func save(_ script: Script) async throws(LabError)
    func delete(named name: String) async throws(LabError)
    /// 名前を変える。同じ名前のスクリプトがあれば失敗する。
    func rename(named name: String, to newName: String) async throws(LabError)
}

// MARK: - 作る

public protocol ForgeModelUseCase: Sendable {
    /// モデルを作り、`name` の名前でモデルのフォルダ（アダプタならアダプタのフォルダ）に置いて記録する。
    func callAsFunction(_ job: ForgeJob, name: String) -> AsyncThrowingStream<ForgeEvent, any Error>
}

public protocol EvaluateModelsUseCase: Sendable {
    /// Vault の `folder` の下のノートでパープレキシティを測り、`prompts` への生成を並べる。
    func callAsFunction(
        _ targets: [EvaluationTarget], folder: String, prompts: [String], maxTokens: Int
    ) -> AsyncThrowingStream<EvaluationEvent, any Error>
}

public protocol DeleteForgedModelUseCase: Sendable {
    /// 手元に作ったモデルのフォルダを消す。
    func callAsFunction(deleting path: String)
}

public protocol ScratchUseCase: Sendable {
    func run(session: String, code: String, model: String?, adapter: String?) -> AsyncThrowingStream<
        ScratchOutput, any Error
    >
    func reset(session: String) async throws(LabError)
    func scripts() async throws(LabError) -> [Script]
    func save(_ script: Script) async throws(LabError)
    /// スクリプトをまとめて消す。
    func delete(scriptsNamed names: [String]) async throws(LabError)
    func rename(scriptNamed name: String, to newName: String) async throws(LabError)
}

public typealias ForgeUseCases = ForgeModelUseCase & EvaluateModelsUseCase & DeleteForgedModelUseCase

/// 工房の操作。作るたび、比べるたびに記録を残す。
public struct ForgeInteractor: ForgeUseCases {
    private let engine: any ForgeEngine
    private let records: any LabRecordRepository
    private let vault: any VaultRepository
    private let markdown: any MarkdownParsing
    private let files: any LabFileLocations

    public init(
        engine: any ForgeEngine, records: any LabRecordRepository, vault: any VaultRepository,
        markdown: any MarkdownParsing, files: any LabFileLocations
    ) {
        self.engine = engine
        self.records = records
        self.vault = vault
        self.markdown = markdown
        self.files = files
    }

    public func callAsFunction(_ job: ForgeJob, name: String) -> AsyncThrowingStream<ForgeEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var texts: [String] = []
                    var outputPath = files.newModelDirectory(name: name)
                    if case .distill(_, _, let folder, let settings) = job {
                        texts = try await NoteTexts.read(in: folder, vault: vault, markdown: markdown)
                        guard texts.count >= 2 else {
                            throw LabError.engine("蒸留に使えるノートが足りません（2 本以上必要です）")
                        }
                        if settings.loraRank != nil { outputPath = files.newAdapterDirectory(name: name) }
                    }
                    var forged: ForgedModel?
                    for try await event in engine.run(job, texts: texts, outputPath: outputPath) {
                        if case .done(let model) = event { forged = model }
                        continuation.yield(event)
                    }
                    if let forged { try await remember(job, forged: forged, name: name, texts: texts) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func callAsFunction(
        _ targets: [EvaluationTarget], folder: String, prompts: [String], maxTokens: Int
    ) -> AsyncThrowingStream<EvaluationEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let texts = try await NoteTexts.read(in: folder, vault: vault, markdown: markdown)
                    // 長すぎると測るのに時間がかかるので、各ノートの頭を使う
                    let sample = texts.prefix(40).map { String($0.prefix(2000)) }
                    var summaries: [String] = []
                    for try await event in engine.evaluate(
                        targets, texts: Array(sample), prompts: prompts, maxTokens: maxTokens, seed: 0)
                    {
                        if case .result(let result) = event {
                            summaries.append(
                                "\(Self.shortName(result.target.model)): "
                                    + String(format: "PPL %.2f、%.0f トークン/秒", result.perplexity, result.tokensPerSecond))
                        }
                        continuation.yield(event)
                    }
                    try? await records.save(
                        Experiment(
                            kind: .evaluate, model: targets.map { Self.shortName($0.model) }.joined(separator: " / "),
                            prompt: prompts.joined(separator: " / "),
                            parameters: ["ノート": folder.isEmpty ? "すべて" : folder, "本数": "\(sample.count)"],
                            summary: summaries.joined(separator: "、")))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func callAsFunction(deleting path: String) {
        files.remove(path)
    }

    private func remember(_ job: ForgeJob, forged: ForgedModel, name: String, texts: [String]) async throws {
        if case .distill(let teacher, let student, let folder, let settings) = job, forged.kind == .adapter {
            try await records.save(
                Adapter(
                    id: UUID(), name: name, model: student, path: forged.path,
                    settings: LoRASettings(
                        iterations: settings.iterations, rank: settings.loraRank ?? 8,
                        learningRate: settings.learningRate),
                    source: "\(Self.shortName(teacher)) から蒸留（\(folder.isEmpty ? "すべて" : folder)、\(texts.count) 本）",
                    finalLoss: nil, createdAt: .now))
        }
        let size = forged.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?"
        let bits = forged.bitsPerWeight.map { String(format: "、%.2f ビット/重み", $0) } ?? ""
        try? await records.save(
            Experiment(
                kind: .forge, model: Self.shortName(job.sourceModel), prompt: name,
                parameters: job.parameters, summary: "\(job.title)して「\(name)」を作成（\(size)\(bits)）"))
    }

    static func shortName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }
}

extension ForgeJob {
    /// 元のモデル。
    var sourceModel: String {
        switch self {
        case .quantize(let model, _, _), .convert(let model, _, _), .fuse(let model, _, _), .prune(let model, _, _):
            model
        case .merge(let first, let second, _, _): "\(first) + \(second)"
        case .distill(let teacher, let student, _, _): "\(teacher) → \(student)"
        }
    }

    /// 記録に残す設定。
    var parameters: [String: String] {
        switch self {
        case .quantize(_, let method, let overrides):
            var result: [String: String] =
                switch method {
                case .affine(let bits, let groupSize, let mixed):
                    ["方式": "本物", "ビット": "\(bits)", "グループ": "\(groupSize)", "混合": mixed ?? "なし"]
                case .simulated(let bits): ["方式": "真似る", "ビット": "\(bits)"]
                case .ternary: ["方式": "3 値（1.58 ビット）"]
                }
            if !overrides.isEmpty {
                result["上書き"] = overrides.map { "\($0.pattern)=\($0.bits.map(String.init) ?? "そのまま")" }
                    .joined(separator: " ")
            }
            return result
        case .convert(_, let dtype, let bits):
            return ["型": dtype, "量子化": bits.map { "\($0) ビット" } ?? "なし"]
        case .fuse(_, let adapter, let dequantize):
            return ["LoRA": (adapter as NSString).lastPathComponent, "戻す": dequantize ? "はい" : "いいえ"]
        case .merge(_, _, let method, let ratio):
            return ["方式": method.rawValue, "割合": "\(ratio)"]
        case .prune(_, let layers, let heads):
            return [
                "層": layers.map(String.init).joined(separator: ","),
                "ヘッド": heads.map { "\($0.layer).\($0.head)" }.joined(separator: ","),
            ]
        case .distill(_, _, let folder, let settings):
            return [
                "ノート": folder.isEmpty ? "すべて" : folder, "反復": "\(settings.iterations)",
                "温度": "\(settings.temperature)", "alpha": "\(settings.alpha)",
                "LoRA": settings.loraRank.map { "ランク \($0)" } ?? "なし（全体を学習）",
            ]
        }
    }
}

// MARK: - 書く

public struct ScratchInteractor: ScratchUseCase {
    private let engine: any ScratchEngine
    private let scriptsRepository: any ScriptRepository
    private let records: any LabRecordRepository

    public init(engine: any ScratchEngine, scripts: any ScriptRepository, records: any LabRecordRepository) {
        self.engine = engine
        self.scriptsRepository = scripts
        self.records = records
    }

    public func run(
        session: String, code: String, model: String?, adapter: String?
    ) -> AsyncThrowingStream<ScratchOutput, any Error> {
        let engine = engine
        let records = records
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var summary = "実行"
                    for try await output in engine.run(session: session, code: code, model: model, adapter: adapter) {
                        switch output {
                        case .done(let seconds): summary = String(format: "%.1f 秒で終了", seconds)
                        case .error(let message, _): summary = "失敗: \(message)"
                        default: break
                        }
                        continuation.yield(output)
                    }
                    try? await records.save(
                        Experiment(
                            kind: .script, model: model.map(ForgeInteractor.shortName) ?? "なし",
                            prompt: String(code.prefix(400)), parameters: [:], summary: summary))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reset(session: String) async throws(LabError) {
        try await engine.reset(session: session)
    }

    public func scripts() async throws(LabError) -> [Script] {
        try await scriptsRepository.scripts()
    }

    public func save(_ script: Script) async throws(LabError) {
        try await scriptsRepository.save(script)
    }

    public func delete(scriptsNamed names: [String]) async throws(LabError) {
        for name in names {
            try await scriptsRepository.delete(named: name)
        }
    }

    public func rename(scriptNamed name: String, to newName: String) async throws(LabError) {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { throw .storage("スクリプトの名前が空です") }
        guard newName != name else { return }
        try await scriptsRepository.rename(named: name, to: newName)
    }
}

/// Vault のフォルダの下のノートの本文（フロントマターを除く）。
enum NoteTexts {
    static func read(in folder: String, vault: any VaultRepository, markdown: any MarkdownParsing) async throws
        -> [String]
    {
        let tree = try await vault.loadTree()
        let prefix = folder.isEmpty ? "" : folder.hasSuffix("/") ? folder : folder + "/"
        var texts: [String] = []
        for file in tree.files where file.kind == .markdown && file.path.hasPrefix(prefix) {
            guard let source = try? await vault.readText(at: file.path) else { continue }
            let body = markdown.analyze(source, path: file.path).body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { texts.append(body) }
        }
        return texts
    }
}
