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

/// Python のスクラッチ。左にスクリプトの一覧、中央にエディタ、下に出力。
struct ScratchView: View {
    @Bindable var viewModel: ScratchViewModel
    @State private var editor = TextEditorSession()

    var body: some View {
        HStack(spacing: 0) {
            List(
                selection: Binding(
                    get: { viewModel.selectedScriptName },
                    set: { name in if let name { Task { await viewModel.open(name) } } }
                )
            ) {
                Section("見本") {
                    ForEach(viewModel.scripts.filter(\.isTemplate)) { Text($0.name).tag($0.name) }
                }
                Section("保存したもの") {
                    ForEach(viewModel.scripts.filter { !$0.isTemplate }) { script in
                        Text(script.name).tag(script.name)
                            .contextMenu {
                                Button("削除", role: .destructive) { Task { await viewModel.delete(script.name) } }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            Divider()
            SplitPane(.vertical, fraction: 0.6, minFirst: 200, minSecond: 160) {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    TextEditorView(
                        session: editor, text: $viewModel.code, syntax: .code(language: "python"),
                        scrollToLine: .constant(nil), onOpen: { _ in }
                    )
                    .accessibilityIdentifier("scratch-editor")
                }
            } second: {
                ScratchOutputView(viewModel: viewModel)
            }
        }
        .task { await viewModel.load() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("名前", text: $viewModel.scriptName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Button("保存", systemImage: "square.and.arrow.down") { Task { await viewModel.save() } }
                .help("スクリプトを保存する")
            Picker("モデル", selection: $viewModel.model) {
                Text("載せない").tag("")
                ForEach(viewModel.models, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 320)
            Spacer()
            Button("変数を消す", systemImage: "arrow.counterclockwise") { Task { await viewModel.reset() } }
                .help("これまでの実行で作った変数を消す")
            if viewModel.isRunning {
                Button("止める", systemImage: "stop.fill") { viewModel.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button("実行", systemImage: "play.fill") { viewModel.run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("実行（⌘↩）")
            }
        }
        .labelStyle(.iconOnly)
        .padding(8)
    }
}

/// 実行の出力（文字、表、図、エラー）。
private struct ScratchOutputView: View {
    let viewModel: ScratchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("出力").font(.headline)
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.orange).lineLimit(2)
                }
                Spacer()
                Button("消す", systemImage: "trash") { viewModel.clearOutputs() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.outputs) { output in
                            OutputRow(kind: output.kind).id(output.id)
                        }
                        if viewModel.isRunning {
                            ProgressView().controlSize(.small)
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
