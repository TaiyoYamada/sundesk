//
//  ScratchViewModel.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// Python のスクリプト（実験室の主役）。エンジンの中で、載せたモデルに直接コードを書いて動かす。
///
/// スクリプトは 1 つずつファイルに保存する。書き換えると少し待って自動で保存する。
@MainActor
@Observable
public final class ScratchViewModel {
    public private(set) var scripts: [ScriptItem] = []
    /// 一覧で選んでいるスクリプト（⇧ と ⌘ で複数選べる）。
    public var selection: Set<String> = []
    /// 開いているスクリプト。
    public private(set) var currentName: String?
    public var code = "" {
        didSet { if code != oldValue { scheduleAutosave() } }
    }
    /// 最後に保存した本文。
    public private(set) var savedCode = ""
    public var model = LabViewModel.suggestedModels[0]
    public private(set) var models: [String] = LabViewModel.suggestedModels
    public private(set) var outputs: [ScratchOutputItem] = []
    public private(set) var isRunning = false
    /// 実行を始めた時刻（実行中の経過時間の表示に使う）。
    public private(set) var runStartedAt: Date?
    public var errorMessage: String?

    /// 見本の名前（新しいスクリプトの元にできる）。
    public static let templateNames = ScriptTemplates.all.map(\.name)
    /// スクリプトの中で最初から使える名前（補完に出す）。
    public static let scratchNames = [
        "model", "tokenizer", "mx", "nn", "np", "plt", "generate", "show", "adapter", "mlx", "numpy", "matplotlib",
    ]

    /// 書き換えていて、まだ保存していないか。
    public var isDirty: Bool { currentName != nil && code != savedCode }

    /// エンジンの中の変数の入れ物。リセットすると新しくする。
    @ObservationIgnored private var session = UUID().uuidString
    @ObservationIgnored private let scratch: any ScratchUseCase
    @ObservationIgnored private let modelManagement: any ModelManagementUseCase
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    /// - Parameter autosaveDelay: 書き換えてから自動で保存するまでの時間。
    public init(
        scratch: any ScratchUseCase, modelManagement: any ModelManagementUseCase,
        autosaveDelay: Duration = .seconds(1)
    ) {
        self.scratch = scratch
        self.modelManagement = modelManagement
        self.autosaveDelay = autosaveDelay
    }

    // MARK: - 一覧

    public func load() async {
        await reloadScripts()
        if let local = try? await modelManagement.localModels() {
            let llms = local.filter { $0.kind == .llm }.map(\.id)
            models = LabViewModel.suggestedModels + llms.filter { !LabViewModel.suggestedModels.contains($0) }
        }
        if currentName == nil, let first = scripts.first {
            await open(first.name)
        }
    }

    private func reloadScripts() async {
        let saved = (try? await scratch.scripts()) ?? []
        scripts = saved.map(ScriptItem.init)
        selection = selection.filter { name in scripts.contains { $0.name == name } }
    }

    /// スクリプトを開く。開いていたものは、書き換えていれば先に保存する。
    public func open(_ name: String) async {
        guard name != currentName else { return }
        await save()
        let saved = (try? await scratch.scripts()) ?? []
        guard let script = saved.first(where: { $0.name == name }) else { return }
        currentName = name
        savedCode = script.code
        code = script.code
        if !selection.contains(name) { selection = [name] }
    }

    /// 一覧の選択が変わったとき。1 つだけ選んだら、それを開く。
    public func selectionChanged() async {
        if selection.count == 1, let name = selection.first, name != currentName {
            await open(name)
        }
    }

    /// 新しいスクリプトを作って開く。`template` を渡すと、その見本を写して作る。
    public func newScript(template: String? = nil) async {
        let source = ScriptTemplates.all.first { $0.name == template }
        let empty = ScriptTemplates.all.last?.code ?? ""
        let name = uniqueName(source?.name ?? "無題")
        await create(Script(name: name, code: source?.code ?? empty))
    }

    /// 選んだスクリプトを複製して開く。
    public func duplicate(_ name: String) async {
        await save()
        guard let script = ((try? await scratch.scripts()) ?? []).first(where: { $0.name == name }) else { return }
        await create(Script(name: uniqueName("\(name) のコピー"), code: script.code))
    }

    private func create(_ script: Script) async {
        do {
            try await scratch.save(script)
            await reloadScripts()
            await open(script.name)
        } catch {
            errorMessage = error.message
        }
    }

    /// 名前を変える。変えられたら true。
    @discardableResult
    public func rename(_ name: String, to newName: String) async -> Bool {
        let newName = Self.fileSafe(newName.trimmingCharacters(in: .whitespaces))
        guard !newName.isEmpty else {
            errorMessage = "スクリプトの名前を入れてください"
            return false
        }
        guard newName != name else { return true }
        if scripts.contains(where: { $0.name == newName }) {
            errorMessage = "「\(newName)」という名前のスクリプトがもうあります"
            return false
        }
        if name == currentName { await save() }
        do {
            try await scratch.rename(scriptNamed: name, to: newName)
        } catch {
            errorMessage = error.message
            return false
        }
        if name == currentName { currentName = newName }
        if selection.remove(name) != nil { selection.insert(newName) }
        await reloadScripts()
        return true
    }

    /// スクリプトをまとめて消す。開いていたものを消したら、残りの先頭を開く。
    public func delete(_ names: Set<String>) async {
        guard !names.isEmpty else { return }
        if let currentName, names.contains(currentName) {
            // 消したファイルを自動保存で作り直さないように、保存を止める
            autosaveTask?.cancel()
            self.currentName = nil
            savedCode = ""
            code = ""
        }
        do {
            try await scratch.delete(scriptsNamed: Array(names))
        } catch {
            errorMessage = error.message
        }
        selection.subtract(names)
        await reloadScripts()
        if currentName == nil, let first = scripts.first {
            await open(first.name)
        }
    }

    // MARK: - 保存

    /// 開いているスクリプトを、書き換えていれば保存する。
    public func save() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard let currentName, code != savedCode else { return }
        let snapshot = code
        do {
            try await scratch.save(Script(name: currentName, code: snapshot))
            // 保存しているあいだに別のスクリプトを開いていたら、印を変えない
            if self.currentName == currentName { savedCode = snapshot }
            if let index = scripts.firstIndex(where: { $0.name == currentName }) {
                scripts[index] = ScriptItem(Script(name: currentName, code: snapshot))
            }
        } catch {
            errorMessage = error.message
        }
    }

    private func scheduleAutosave() {
        guard isDirty else { return }
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// `base` と重ならない名前（重なれば「base 2」「base 3」…）。
    private func uniqueName(_ base: String) -> String {
        let base = Self.fileSafe(base)
        let names = Set(scripts.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// ファイルの名前に使えない文字を「-」にする（保存するときと同じ規則）。
    private static func fileSafe(_ name: String) -> String {
        name.replacing(/[\/:\\]/, with: "-")
    }

    // MARK: - 実行

    /// スクリプト全体を実行する。
    public func run() {
        run(code)
    }

    /// 渡したコード（選んだ範囲やカーソルの行）を実行する。変数は前の実行から引き継ぐ。
    public func run(_ code: String) {
        guard !isRunning, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        outputs.append(ScratchOutputItem(id: outputs.count, kind: .code(code)))
        isRunning = true
        runStartedAt = .now
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
            runStartedAt = nil
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
    /// 最初のコメントの行（一覧に添える説明）。
    public let summary: String

    init(_ script: Script) {
        name = script.name
        summary =
            script.code.split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("#") }
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) } ?? ""
    }
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
