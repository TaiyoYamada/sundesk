//
//  ScriptListView.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskDesignSystem
import SwiftUI

/// スクリプトの一覧。クリックで開き、⇧クリックと⌘クリックで複数選んで、⌫ か右クリックでまとめて消す。
struct ScriptListView: View {
    @Bindable var viewModel: ScratchViewModel
    let sessions: ScriptEditorSessions
    /// 「名前を変更」を選んだとき（名前の欄に移る）。
    let rename: () -> Void
    @State private var pendingDeletion: Set<String>?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $viewModel.selection) {
                Section("スクリプト") {
                    ForEach(viewModel.scripts) { script in
                        row(script).tag(script.name)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { names in
                contextMenu(names)
            }
            .onDeleteCommand { requestDeletion(viewModel.selection) }
            .focusesOnClick()
            .onChange(of: viewModel.selection) { Task { await viewModel.selectionChanged() } }
            .accessibilityIdentifier("scratch-scripts")
            Divider()
            bottomBar
        }
        .confirmsDeletion($pendingDeletion) { names in
            DeletionTitle.make(count: names.count, unit: "個", noun: "スクリプト", name: names.first)
        } delete: { names in
            sessions.remove(names)
            Task { await viewModel.delete(names) }
        }
    }

    private func row(_ script: ScriptItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(script.name).lineLimit(1)
                if script.name == viewModel.currentName, viewModel.isDirty {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                        .accessibilityLabel("未保存")
                }
            }
            if !script.summary.isEmpty {
                Text(script.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func contextMenu(_ names: Set<String>) -> some View {
        if names.isEmpty {
            newMenuItems
        } else {
            if names.count == 1, let name = names.first {
                Button("名前を変更…") {
                    Task {
                        await viewModel.open(name)
                        rename()
                    }
                }
                Button("複製") { Task { await viewModel.duplicate(name) } }
                Divider()
            }
            Button(names.count == 1 ? "削除…" : "\(names.count) 個を削除…", role: .destructive) {
                requestDeletion(names)
            }
        }
    }

    @ViewBuilder
    private var newMenuItems: some View {
        Button("新しいスクリプト") { Task { await viewModel.newScript() } }
        Section("見本から作る") {
            ForEach(ScratchViewModel.templateNames, id: \.self) { name in
                Button(name) { Task { await viewModel.newScript(template: name) } }
            }
        }
    }

    /// Finder や Xcode の一覧の下と同じ、＋と−の帯。
    private var bottomBar: some View {
        HStack(spacing: 2) {
            Menu {
                newMenuItems
            } label: {
                Label("新しいスクリプト", systemImage: "plus")
            } primaryAction: {
                Task { await viewModel.newScript() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("新しいスクリプト（長押しで見本から作る）")
            Button("選んだスクリプトを削除", systemImage: "minus") { requestDeletion(viewModel.selection) }
                .buttonStyle(.borderless)
                .disabled(viewModel.selection.isEmpty)
                .help("選んだスクリプトを削除（⌫）")
            Spacer()
            if viewModel.selection.count > 1 {
                Text("\(viewModel.selection.count) 個を選択").font(.caption).foregroundStyle(.secondary)
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func requestDeletion(_ names: Set<String>) {
        guard !names.isEmpty else { return }
        pendingDeletion = names
    }
}
