//
//  LabScreen.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SwiftUI

/// 実験室のタブ。左で何を見るかを選び、上でモデルとプロンプトを決めて実行する。
public struct LabScreen: View {
    @Bindable private var viewModel: LabViewModel

    public init(viewModel: LabViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            List(selection: $viewModel.section) {
                Section("覗く") {
                    ForEach([LabViewModel.Section.tokens, .nextToken, .generate, .attention, .logitLens, .activations])
                    {
                        Label($0.title, systemImage: $0.systemImage).tag($0)
                    }
                }
                Section("いじる") {
                    ForEach([LabViewModel.Section.lora, .steering]) {
                        Label($0.title, systemImage: $0.systemImage).tag($0)
                    }
                }
                Section {
                    Label(LabViewModel.Section.records.title, systemImage: LabViewModel.Section.records.systemImage)
                        .tag(LabViewModel.Section.records)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            Divider()
            VStack(spacing: 0) {
                if viewModel.section.usesPrompt {
                    PromptBar(viewModel: viewModel)
                    Divider()
                } else if viewModel.section == .lora {
                    ModelBar(viewModel: viewModel)
                    Divider()
                }
                if let status = viewModel.status {
                    ProgressBanner(
                        title: status, fraction: viewModel.section == .lora ? viewModel.trainingProgress : nil)
                    Divider()
                }
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    Divider()
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await viewModel.load() }
        .task { await viewModel.observeRecords() }
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
        case .records: RecordsView(viewModel: viewModel)
        }
    }
}

/// モデルの選択。
struct ModelBar: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        HStack {
            Picker("モデル", selection: $viewModel.model) {
                ForEach(viewModel.models, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 420)
            Spacer()
        }
        .padding(12)
    }
}

/// モデル、プロンプト、実行。
struct PromptBar: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("モデル", selection: $viewModel.model) {
                    ForEach(viewModel.models, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 420)
                Toggle("チャット形式で包む", isOn: $viewModel.chatTemplate)
                    .help("指示モデルに質問するときは、チャットの決まった形に包むと自然に答える")
                Spacer()
                if viewModel.isRunning {
                    Button("止める", systemImage: "stop.fill") { viewModel.cancel() }
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("実行", systemImage: "play.fill") { viewModel.run() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .help("実行（⌘↩）")
                }
            }
            TextEditor(text: $viewModel.prompt)
                .font(.system(size: 13))
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .accessibilityIdentifier("lab-prompt")
        }
        .padding(12)
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
