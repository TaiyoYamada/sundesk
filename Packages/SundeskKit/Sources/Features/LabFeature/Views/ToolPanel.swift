//
//  ToolPanel.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskDesignSystem
import SwiftUI

/// 実験室の右のパネル。上で道具を選び、その道具の設定と結果を出す。
struct ToolPanel: View {
    @Bindable var viewModel: LabViewModel
    let forge: ForgeViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.section.usesPrompt {
                PromptBar(viewModel: viewModel)
                Divider()
            } else if viewModel.section == .lora {
                ModelBar(viewModel: viewModel)
                Divider()
            }
            if let status = viewModel.status {
                ProgressBanner(title: status, fraction: viewModel.section == .lora ? viewModel.trainingProgress : nil)
                Divider()
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("道具", selection: $viewModel.section) {
                ForEach(LabViewModel.sectionGroups) { group in
                    Section(group.title) {
                        ForEach(group.sections) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("lab-tool-picker")
            Spacer()
            Button("パネルを閉じる", systemImage: "xmark") { isPresented = false }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("道具のパネルを閉じる（⌃⌘T）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.section {
        case .tokens: TokensView(viewModel: viewModel)
        case .nextToken: NextTokenView(viewModel: viewModel)
        case .generate: GenerateView(viewModel: viewModel)
        case .attention: AttentionView(viewModel: viewModel)
        case .logitLens: LogitLensView(viewModel: viewModel)
        case .activations: ActivationsView(viewModel: viewModel)
        case .lora: LoRAView(viewModel: viewModel)
        case .steering: SteeringView(viewModel: viewModel)
        case .distill: DistillView(viewModel: forge)
        case .quantize: QuantizeView(viewModel: forge)
        case .convertMerge: ConvertMergeView(viewModel: forge)
        case .prune: PruneView(viewModel: forge)
        case .evaluate: EvaluateView(viewModel: forge)
        case .records: RecordsView(viewModel: viewModel)
        }
    }
}

/// モデルの選択。
struct ModelBar: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        Picker("モデル", selection: $viewModel.model) {
            ForEach(viewModel.models, id: \.self) { Text($0).tag($0) }
        }
        .padding(10)
    }
}

/// モデル、プロンプト、実行。スクリプトの実行（⌘↩）と分けるため、道具の実行は ⌥⌘↩ にする。
struct PromptBar: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("モデル", selection: $viewModel.model) {
                    ForEach(viewModel.models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                if viewModel.isRunning {
                    Button("止める", systemImage: "stop.fill") { viewModel.cancel() }
                } else {
                    Button("実行", systemImage: "play.fill") { viewModel.run() }
                        .keyboardShortcut(.return, modifiers: [.command, .option])
                        .help("道具を実行（⌥⌘↩）")
                }
            }
            TextEditor(text: $viewModel.prompt)
                .font(.system(size: 13))
                .frame(height: 56)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .accessibilityIdentifier("lab-prompt")
            Toggle("チャット形式で包む", isOn: $viewModel.chatTemplate)
                .controlSize(.small)
                .help("指示モデルに質問するときは、チャットの決まった形に包むと自然に答える")
        }
        .padding(10)
    }
}

/// まだ実行していないときの表示。
struct LabPlaceholder: View {
    let section: LabViewModel.Section
    let description: String

    var body: some View {
        ContentUnavailableView(section.title, systemImage: section.systemImage, description: Text(description))
    }
}

// MARK: - 記録

/// 実験の記録。⇧クリックと⌘クリックで複数選び、⌫ か右クリックでまとめて消す。
struct RecordsView: View {
    let viewModel: LabViewModel
    @State private var selection = Set<ExperimentItem.ID>()
    @State private var pendingDeletion: Set<ExperimentItem.ID>?

    var body: some View {
        if viewModel.experiments.isEmpty {
            LabPlaceholder(section: .records, description: "道具やスクリプトを実行するたびに、モデル、プロンプト、設定、結果の要約を記録します。")
        } else {
            VStack(spacing: 0) {
                List(viewModel.experiments, selection: $selection) { item in
                    RecordRow(item: item)
                }
                .contextMenu(forSelectionType: ExperimentItem.ID.self) { ids in
                    if !ids.isEmpty {
                        Button(ids.count == 1 ? "削除…" : "\(ids.count) 件を削除…", role: .destructive) {
                            pendingDeletion = ids
                        }
                    }
                }
                .onDeleteCommand { if !selection.isEmpty { pendingDeletion = selection } }
                .focusesOnClick()
                .accessibilityIdentifier("lab-records")
                Divider()
                HStack {
                    Text(selection.isEmpty ? "\(viewModel.experiments.count) 件" : "\(selection.count) 件を選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("削除…", role: .destructive) { pendingDeletion = selection }
                        .controlSize(.small)
                        .disabled(selection.isEmpty)
                        .help("選んだ記録を削除（⌫）")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .confirmsDeletion($pendingDeletion) { ids in
                DeletionTitle.make(count: ids.count, unit: "件", noun: "記録", name: nil)
            } delete: { ids in
                selection.subtract(ids)
                Task { await viewModel.deleteExperiments(ids) }
            }
        }
    }
}

private struct RecordRow: View {
    let item: ExperimentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.kind).fontWeight(.semibold)
                Text(item.model).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(item.date).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if !item.prompt.isEmpty {
                Text(item.prompt).font(.callout).lineLimit(2)
            }
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if !item.parameters.isEmpty {
                Text(item.parameters).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .help(item.prompt)
    }
}
