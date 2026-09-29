//
//  ScratchViewModel.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// Python のスクラッチ。エンジンの中で、載せたモデルに直接コードを書いて動かす。
@MainActor
@Observable
public final class ScratchViewModel {
    public private(set) var scripts: [ScriptItem] = []
    public var selectedScriptName: String?
    public var code = ScriptTemplates.all[0].code
    public var scriptName = ScriptTemplates.all[0].name
    public var model = LabViewModel.suggestedModels[0]
    public private(set) var models: [String] = LabViewModel.suggestedModels
    public private(set) var outputs: [ScratchOutputItem] = []
    public private(set) var isRunning = false
    public var errorMessage: String?

    /// エンジンの中の変数の入れ物。リセットすると新しくする。
    @ObservationIgnored private var session = UUID().uuidString
    @ObservationIgnored private let scratch: any ScratchUseCase
    @ObservationIgnored private let modelManagement: any ModelManagementUseCase
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(scratch: any ScratchUseCase, modelManagement: any ModelManagementUseCase) {
        self.scratch = scratch
        self.modelManagement = modelManagement
    }

    public func load() async {
        let saved = (try? await scratch.scripts()) ?? []
        scripts =
            ScriptTemplates.all.map { ScriptItem(name: $0.name, isTemplate: true) }
            + saved.map { ScriptItem(name: $0.name, isTemplate: false) }
        if let local = try? await modelManagement.localModels() {
            let llms = local.filter { $0.kind == .llm }.map(\.id)
            models = LabViewModel.suggestedModels + llms.filter { !LabViewModel.suggestedModels.contains($0) }
        }
    }

    /// スクリプトを開く（見本か、保存したもの）。
    public func open(_ name: String) async {
        let saved = (try? await scratch.scripts()) ?? []
        guard let script = (ScriptTemplates.all + saved).first(where: { $0.name == name }) else { return }
        selectedScriptName = name
        scriptName = name
        code = script.code
    }

    public func save() async {
        let name = scriptName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "スクリプトの名前を入れてください"
            return
        }
        do {
            try await scratch.save(Script(name: name, code: code))
            selectedScriptName = name
            await load()
        } catch {
            errorMessage = error.message
        }
    }

    public func delete(_ name: String) async {
        try? await scratch.delete(scriptNamed: name)
        await load()
    }

    // MARK: - 実行

    public func run() {
        guard !isRunning else { return }
        errorMessage = nil
        outputs.append(ScratchOutputItem(id: outputs.count, kind: .code(code)))
        isRunning = true
        let stream = scratch.run(session: session, code: code, model: model.isEmpty ? nil : model, adapter: nil)
        task = Task {
            do {
                for try await output in stream {
                    append(output)
                }
            } catch is CancellationError {
                outputs.append(ScratchOutputItem(id: outputs.count, kind: .note("止めました")))
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
            task = nil
        }
    }

    public func stop() {
        task?.cancel()
    }

    public func clearOutputs() {
        outputs = []
    }

    /// 変数をすべて消す。
    public func reset() async {
        stop()
        try? await scratch.reset(session: session)
        session = UUID().uuidString
        outputs.append(ScratchOutputItem(id: outputs.count, kind: .note("変数を消しました")))
    }

    private func append(_ output: ScratchOutput) {
        let kind: ScratchOutputItem.Kind
        switch output {
        case .stdout(let text):
            // 続けて届いた標準出力は 1 つにまとめる
            if case .text(let previous, false) = outputs.last?.kind {
                outputs[outputs.count - 1] = ScratchOutputItem(
                    id: outputs.count - 1, kind: .text(previous + text, isError: false))
                return
            }
            kind = .text(text, isError: false)
        case .stderr(let text): kind = .text(text, isError: true)
        case .image(let data): kind = .image(data)
        case .table(let columns, let rows): kind = .table(columns: columns, rows: rows)
        case .value(let repr): kind = .value(repr)
        case .done(let seconds): kind = .note(String(format: "%.2f 秒", seconds))
        case .error(let message, let traceback): kind = .error(message: message, traceback: traceback)
        }
        outputs.append(ScratchOutputItem(id: outputs.count, kind: kind))
    }
}

public struct ScriptItem: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// 最初から用意した見本か。
    public let isTemplate: Bool
}

public struct ScratchOutputItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// 実行したコード（区切りとして出す）。
        case code(String)
        case text(String, isError: Bool)
        case image(Data)
        case table(columns: [String], rows: [[String]])
        case value(String)
        case error(message: String, traceback: String?)
        case note(String)
    }

    public let id: Int
    public let kind: Kind
}
