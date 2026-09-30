//
//  ScratchView.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskDesignSystem
import SundeskEditorUI
import SwiftUI

/// スクリプトごとのエディタ。切り替えても、取り消しの履歴とスクロール位置を残す。
@MainActor
final class ScriptEditorSessions {
    private var sessions: [String: TextEditorSession] = [:]

    func session(for name: String) -> TextEditorSession {
        if let session = sessions[name] { return session }
        let session = TextEditorSession()
        sessions[name] = session
        return session
    }

    func rename(_ name: String, to newName: String) {
        sessions[newName] = sessions.removeValue(forKey: name)
    }

    func remove(_ names: Set<String>) {
        for name in names { sessions[name] = nil }
    }
}

/// Python のスクリプトのエディタ（実験室の主役）。上に名前と実行、中央にエディタ、下に出力。
struct ScratchView: View {
    @Bindable var viewModel: ScratchViewModel
    let sessions: ScriptEditorSessions
    let lab: LabViewModel
    @Binding var showsScripts: Bool
    @Binding var showsTools: Bool
    /// 一覧から「名前を変更」が選ばれた。
    @Binding var renameRequested: Bool
    @State private var nameDraft = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
                Divider()
            }
            if let name = viewModel.currentName {
                SplitPane(.vertical, fraction: 0.64, minFirst: 160, minSecond: 110) {
                    TextEditorView(
                        session: sessions.session(for: name), text: $viewModel.code, syntax: .code(language: "python"),
                        scrollToLine: .constant(nil), completions: ScratchViewModel.scratchNames, onOpen: { _ in }
                    )
                    .id(name)
                    .accessibilityIdentifier("scratch-editor")
                } second: {
                    ScratchOutputView(viewModel: viewModel)
                }
            } else {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.currentName, initial: true) { nameDraft = viewModel.currentName ?? "" }
        .onChange(of: renameRequested) {
            guard renameRequested else { return }
            isNameFocused = true
            renameRequested = false
        }
    }

    // MARK: - 上の帯

    private var header: some View {
        HStack(spacing: 6) {
            Button("スクリプトの一覧", systemImage: "sidebar.left") { showsScripts.toggle() }
                .buttonStyle(.borderless)
                .help(showsScripts ? "スクリプトの一覧を隠す" : "スクリプトの一覧を表示")
            if viewModel.currentName != nil {
                nameField
            }
            Spacer(minLength: 8)
            Picker("モデル", selection: $viewModel.model) {
                Text("載せない").tag("")
                ForEach(viewModel.models, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(minWidth: 80, maxWidth: 240)
            .help("スクリプトの model と tokenizer に載せるモデル")
            runControls
            Divider().frame(height: 18)
            editorMenu
            toolsMenu
            Button("道具のパネル", systemImage: "sidebar.right") { showsTools.toggle() }
                .buttonStyle(.borderless)
                .keyboardShortcut("t", modifiers: [.command, .control])
                .help(showsTools ? "道具のパネルを隠す（⌃⌘T）" : "道具のパネルを表示（⌃⌘T）")
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// スクリプトの名前（書き換えて ↩ で名前を変える）と、未保存の印。
    private var nameField: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.secondary)
                .frame(width: 7, height: 7)
                .opacity(viewModel.isDirty ? 1 : 0)
                .help("まだ保存していない変更があります（すぐに自動で保存します）")
                .accessibilityLabel(viewModel.isDirty ? "未保存" : "保存済み")
            TextField("名前", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($isNameFocused)
                .frame(minWidth: 60, maxWidth: 260)
                .onSubmit(commitRename)
                .onChange(of: isNameFocused) { if !isNameFocused { commitRename() } }
                .help("名前を書き換えて ↩ で変える")
        }
    }

    private var runControls: some View {
        HStack(spacing: 6) {
            if viewModel.isRunning {
                RunningLabel(startedAt: viewModel.runStartedAt)
                Button("止める", systemImage: "stop.fill") { viewModel.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("止める（⌘.）")
            } else {
                Button("選んだ部分を実行", systemImage: "text.line.first.and.arrowtriangle.forward") { runSelection() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(viewModel.currentName == nil)
                    .help("選んだ部分か、カーソルの行だけを実行（⇧⌘↩）")
                Button("実行", systemImage: "play.fill") { viewModel.run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                    .disabled(viewModel.currentName == nil)
                    .help("スクリプト全体を実行（⌘↩）")
            }
        }
    }

    /// 保存、検索、変数の消去など。
    private var editorMenu: some View {
        HStack(spacing: 6) {
            Button("検索と置換", systemImage: "magnifyingglass") { currentSession?.showFind(replacing: false) }
                .buttonStyle(.borderless)
                .keyboardShortcut("f", modifiers: .command)
                .disabled(viewModel.currentName == nil)
                .help("検索と置換（⌘F）")
            Button("保存", systemImage: "square.and.arrow.down") { Task { await viewModel.save() } }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!viewModel.isDirty)
                .help("保存（⌘S）。書き換えると自動でも保存します")
        }
    }

    /// 道具（トークン、Attention、LoRA…）をパネルで開く。
    private var toolsMenu: some View {
        Menu {
            ForEach(LabViewModel.sectionGroups) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        Button(section.title, systemImage: section.systemImage) {
                            lab.section = section
                            showsTools = true
                        }
                    }
                }
            }
        } label: {
            Label("道具", systemImage: "wrench.and.screwdriver")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("道具をパネルで開く")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("スクリプトがありません", systemImage: "curlybraces.square")
        } description: {
            Text("Python で、載せたモデルの中を直接調べられます。model、tokenizer、mx、np、plt、generate、show が使えます。")
        } actions: {
            Button("新しいスクリプト") { Task { await viewModel.newScript() } }
                .buttonStyle(.borderedProminent)
            Menu("見本から作る") {
                ForEach(ScratchViewModel.templateNames, id: \.self) { name in
                    Button(name) { Task { await viewModel.newScript(template: name) } }
                }
            }
            .fixedSize()
        }
    }

    // MARK: - 操作

    private var currentSession: TextEditorSession? {
        viewModel.currentName.map(sessions.session(for:))
    }

    private func runSelection() {
        guard let session = currentSession else { return }
        viewModel.run(session.selectedTextOrCurrentLine)
    }

    private func commitRename() {
        guard let name = viewModel.currentName, nameDraft != name else { return }
        let draft = nameDraft
        Task {
            if await viewModel.rename(name, to: draft), let newName = viewModel.currentName {
                sessions.rename(name, to: newName)
                nameDraft = newName
            } else {
                nameDraft = viewModel.currentName ?? name
            }
        }
    }
}

/// 実行中の表示（経過時間）。
private struct RunningLabel: View {
    let startedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(String(format: "実行中 %.1f 秒", context.date.timeIntervalSince(startedAt ?? context.date)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }
}

/// 実行の出力（文字、表、図、エラー）。
private struct ScratchOutputView: View {
    let viewModel: ScratchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("出力").font(.headline)
                if viewModel.isRunning {
                    RunningLabel(startedAt: viewModel.runStartedAt)
                }
                Spacer()
                Button("変数を消す", systemImage: "arrow.counterclockwise") { Task { await viewModel.reset() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("これまでの実行で作った変数を消す")
                Button("出力を消す", systemImage: "trash") { viewModel.clearOutputs() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(viewModel.outputs.isEmpty)
                    .help("出力を消す（⌘K）")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.outputs.isEmpty && !viewModel.isRunning {
                            Text("⌘↩ でスクリプト全体を、⇧⌘↩ で選んだ部分かカーソルの行を実行します。変数は次の実行に引き継ぎます。Esc で名前を補完します。")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(viewModel.outputs) { output in
                            OutputRow(kind: output.kind).id(output.id)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.outputs.count) { proxy.scrollTo(viewModel.outputs.last?.id, anchor: .bottom) }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct OutputRow: View {
    let kind: ScratchOutputItem.Kind

    var body: some View {
        switch kind {
        case .code(let code):
            Text(code.split(separator: "\n").prefix(2).joined(separator: "\n") + (code.contains("\n") ? " …" : ""))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        case .text(let text, let isError):
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .foregroundStyle(isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: min(image.size.width, 720))
            }
        case .table(let columns, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            Text(column).fontWeight(.semibold)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell).monospacedDigit()
                            }
                        }
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            }
        case .value(let repr):
            Text(repr).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        case .error(let message, let traceback):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).foregroundStyle(.red).fontWeight(.medium)
                if let traceback {
                    Text(traceback).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
        case .note(let note):
            Text(note).font(.caption).foregroundStyle(.tertiary)
        }
    }
}
