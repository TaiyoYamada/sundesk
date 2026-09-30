//
//  ScratchViewModelTests.swift
//  LabFeatureTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import LabFeature
import SundeskDomain
import Testing

@MainActor
@Suite("ScratchViewModel")
struct ScratchViewModelTests {
    private func makeViewModel(_ store: ScriptStore) -> ScratchViewModel {
        ScratchViewModel(scratch: store, modelManagement: ModelsStub(), autosaveDelay: .milliseconds(10))
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("読み込むと、保存したスクリプトの先頭を開く")
    func opensFirstScript() async {
        let store = ScriptStore([Script(name: "a", code: "# 説明\nx = 1"), Script(name: "b", code: "y = 2")])
        let viewModel = makeViewModel(store)

        await viewModel.load()

        #expect(viewModel.scripts.map(\.name) == ["a", "b"])
        #expect(viewModel.scripts.first?.summary == "説明")
        #expect(viewModel.currentName == "a")
        #expect(viewModel.code == "# 説明\nx = 1")
        #expect(viewModel.selection == ["a"])
        #expect(!viewModel.isDirty)
    }

    @Test("書き換えると未保存の印がつき、少し待つと自動で保存する")
    func autosaves() async {
        let store = ScriptStore([Script(name: "a", code: "x = 1")])
        let viewModel = makeViewModel(store)
        await viewModel.load()

        viewModel.code = "x = 2"
        #expect(viewModel.isDirty)
        await waitUntil { await store.code(of: "a") == "x = 2" }

        #expect(await store.code(of: "a") == "x = 2")
        #expect(!viewModel.isDirty)
    }

    @Test("別のスクリプトを開く前に、書き換えたものを保存する")
    func savesBeforeSwitching() async {
        let store = ScriptStore([Script(name: "a", code: "x = 1"), Script(name: "b", code: "y = 2")])
        let viewModel = ScratchViewModel(scratch: store, modelManagement: ModelsStub(), autosaveDelay: .seconds(60))
        await viewModel.load()

        viewModel.code = "x = 3"
        viewModel.selection = ["b"]
        await viewModel.selectionChanged()

        #expect(await store.code(of: "a") == "x = 3")
        #expect(viewModel.currentName == "b")
        #expect(viewModel.code == "y = 2")
    }

    @Test("新規、見本から、複製は、重ならない名前で作って開く")
    func createsScripts() async {
        let store = ScriptStore([Script(name: "無題", code: "")])
        let viewModel = makeViewModel(store)
        await viewModel.load()

        await viewModel.newScript()
        #expect(viewModel.currentName == "無題 2")
        await viewModel.newScript(template: ScratchViewModel.templateNames[0])
        #expect(viewModel.currentName == ScratchViewModel.templateNames[0])
        #expect(viewModel.code == ScriptTemplates.all[0].code)
        await viewModel.duplicate("無題")
        #expect(viewModel.currentName == "無題 のコピー")

        #expect(Set(await store.names) == ["無題", "無題 2", ScratchViewModel.templateNames[0], "無題 のコピー"])
    }

    @Test("名前を変える。同じ名前があれば断る")
    func renames() async {
        let store = ScriptStore([Script(name: "a", code: "1"), Script(name: "b", code: "2")])
        let viewModel = makeViewModel(store)
        await viewModel.load()

        #expect(await viewModel.rename("a", to: " 層/ノルム "))
        #expect(viewModel.currentName == "層-ノルム")
        #expect(!(await viewModel.rename("層-ノルム", to: "b")))
        #expect(viewModel.errorMessage == "「b」という名前のスクリプトがもうあります")
        #expect(Set(await store.names) == ["層-ノルム", "b"])
    }

    @Test("まとめて消す。開いていたものを消したら、残りの先頭を開き、消したものは作り直さない")
    func deletesInBulk() async {
        let store = ScriptStore([
            Script(name: "a", code: "1"), Script(name: "b", code: "2"), Script(name: "c", code: "3"),
        ])
        let viewModel = makeViewModel(store)
        await viewModel.load()
        viewModel.code = "未保存"

        await viewModel.delete(["a", "b"])
        try? await Task.sleep(for: .milliseconds(40))

        #expect(await store.names == ["c"])
        #expect(viewModel.currentName == "c")
        #expect(viewModel.code == "3")
        #expect(viewModel.selection == ["c"])
    }

    @Test("選んだ部分だけを実行し、空なら実行しない")
    func runsSelection() async {
        let store = ScriptStore([])
        let viewModel = makeViewModel(store)

        viewModel.run("   \n")
        #expect(!viewModel.isRunning)

        viewModel.run("print(1)")
        #expect(viewModel.isRunning)
        await waitUntil { !viewModel.isRunning }
        #expect(await store.ran == ["print(1)"])
        #expect(viewModel.outputs.first?.kind == .code("print(1)"))
    }
}

/// スクリプトをメモリの上に持つ。
actor ScriptStore: ScratchUseCase {
    private var scripts: [String: String]
    private(set) var ran: [String] = []

    init(_ scripts: [Script]) {
        self.scripts = Dictionary(uniqueKeysWithValues: scripts.map { ($0.name, $0.code) })
    }

    var names: [String] { scripts.keys.sorted() }

    func code(of name: String) -> String? { scripts[name] }

    nonisolated func run(
        session: String, code: String, model: String?, adapter: String?
    ) -> AsyncThrowingStream<ScratchOutput, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.record(code)
                continuation.yield(.stdout("1\n"))
                continuation.yield(.done(seconds: 0.1))
                continuation.finish()
            }
        }
    }

    private func record(_ code: String) { ran.append(code) }

    func reset(session: String) async throws(LabError) {}

    func scripts() async throws(LabError) -> [Script] {
        scripts.map { Script(name: $0.key, code: $0.value) }.sorted { $0.name < $1.name }
    }

    func save(_ script: Script) async throws(LabError) { scripts[script.name] = script.code }

    func delete(scriptsNamed names: [String]) async throws(LabError) {
        for name in names { scripts[name] = nil }
    }

    func rename(scriptNamed name: String, to newName: String) async throws(LabError) {
        scripts[newName] = scripts.removeValue(forKey: name)
    }
}
