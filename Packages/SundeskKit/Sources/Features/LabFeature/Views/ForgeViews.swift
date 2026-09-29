//
//  ForgeViews.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Charts
import SundeskDesignSystem
import SwiftUI

/// 工房の画面に共通する枠。左に設定、右に進み具合と結果。
private struct ForgeLayout<Settings: View, Result: View>: View {
    let viewModel: ForgeViewModel
    @ViewBuilder let settings: Settings
    @ViewBuilder let result: Result

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                settings
            }
            .formStyle(.grouped)
            .frame(width: 380)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                if let progress = viewModel.progress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.title).foregroundStyle(.secondary)
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                if let output = viewModel.lastOutput {
                    GroupBox("できたもの") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(output.name).font(.headline)
                            Text(output.detail).foregroundStyle(.secondary)
                            Button("Finder で表示") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: output.path)])
                            }
                            .controlSize(.small)
                            Text("「評価」で元のモデルと比べたり、「生成」や「スクリプト」で使ったりできます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                result
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// モデルを選ぶ。
private struct ModelPicker: View {
    let title: String
    let viewModel: ForgeViewModel
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(viewModel.models) { Text($0.name).tag($0.id) }
        }
    }
}

/// 名前と実行のボタン。
private struct RunSection: View {
    @Bindable var viewModel: ForgeViewModel
    let title: String
    let action: () -> Void

    var body: some View {
        Section {
            TextField("名前（空なら自動）", text: $viewModel.outputName)
            if viewModel.isRunning {
                Button("止める", role: .destructive) { viewModel.cancel() }
            } else {
                Button(title, action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - 量子化

struct QuantizeView: View {
    @Bindable var viewModel: ForgeViewModel

    var body: some View {
        ForgeLayout(viewModel: viewModel) {
            Section {
                ModelPicker(title: "元のモデル", viewModel: viewModel, selection: $viewModel.quantizeModel)
                Picker("方式", selection: $viewModel.quantizeMethod) {
                    ForEach(QuantizeMethodChoice.allCases) { Text($0.title).tag($0) }
                }
                switch viewModel.quantizeMethod {
                case .affine:
                    Picker("ビット", selection: $viewModel.quantizeBits) {
                        ForEach([2, 3, 4, 5, 6, 8], id: \.self) { Text("\($0) ビット").tag($0) }
                    }
                    Picker("グループ", selection: $viewModel.quantizeGroupSize) {
                        ForEach([32, 64, 128], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("層ごとの配分", selection: $viewModel.quantizeMixed) {
                        ForEach(ForgeViewModel.mixedRecipes, id: \.self) { Text($0.isEmpty ? "使わない" : $0).tag($0) }
                    }
                case .simulated:
                    Picker("ビット", selection: $viewModel.quantizeBits) {
                        ForEach(1...8, id: \.self) { Text("\($0) ビット").tag($0) }
                    }
                case .ternary:
                    Text("重みを −1、0、+1 の 3 つの値（と層ごとの倍率）に丸めます。BitNet b1.58 のような極端な圧縮の効き目を、手元のモデルで試せます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("「真似る」は、量子化してすぐ戻した値を保存します。大きさは減りませんが、本物にない 1 ビットや 7 ビットの効き目を試せます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("重みごとの上書き（1 行に「名前の一部=ビット」、ビットが空なら量子化しない）") {
                TextEditor(text: $viewModel.quantizeOverrides)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 60)
            }
            RunSection(viewModel: viewModel, title: "量子化する") { viewModel.quantize() }
        } result: {
            EmptyView()
        }
    }
}

// MARK: - 変換と合成

struct ConvertMergeView: View {
    @Bindable var viewModel: ForgeViewModel
    @State private var mode = 0

    var body: some View {
        ForgeLayout(viewModel: viewModel) {
            Section {
                Picker("やること", selection: $mode) {
                    Text("変換").tag(0)
                    Text("LoRA を焼き込む").tag(1)
                    Text("混ぜる").tag(2)
                }
                .pickerStyle(.segmented)
            }
            switch mode {
            case 0:
                Section {
                    TextField("Hugging Face の ID", text: $viewModel.convertModel)
                    Picker("型", selection: $viewModel.convertDType) {
                        ForEach(["bfloat16", "float16", "float32"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("量子化", selection: $viewModel.convertBits) {
                        Text("しない").tag(Int?.none)
                        ForEach([4, 8], id: \.self) { Text("\($0) ビット").tag(Int?.some($0)) }
                    }
                } footer: {
                    Text("transformers の形式（PyTorch や safetensors）のモデルを MLX に変換します。先に「モデル」のタブで取り込んでください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                RunSection(viewModel: viewModel, title: "変換する") { viewModel.convert() }
            case 1:
                Section {
                    ModelPicker(title: "モデル", viewModel: viewModel, selection: $viewModel.fuseModel)
                    Picker("LoRA", selection: $viewModel.fuseAdapterID) {
                        Text("選ぶ").tag(UUID?.none)
                        ForEach(viewModel.adapters) { Text("\($0.name)（\($0.model)）").tag(UUID?.some($0.id)) }
                    }
                    Toggle("量子化を戻して保存する", isOn: $viewModel.fuseDequantize)
                }
                RunSection(viewModel: viewModel, title: "焼き込む") { viewModel.fuse() }
            default:
                Section {
                    ModelPicker(title: "A", viewModel: viewModel, selection: $viewModel.mergeFirst)
                    ModelPicker(title: "B", viewModel: viewModel, selection: $viewModel.mergeSecond)
                    Toggle("球面で補間する（slerp）", isOn: $viewModel.mergeSlerp)
                    VStack(alignment: .leading) {
                        Text("B の割合 \(String(format: "%.2f", viewModel.mergeRatio))")
                        Slider(value: $viewModel.mergeRatio, in: 0...1)
                    }
                } footer: {
                    Text("同じ構造の 2 つのモデル（元が同じで、別々に学習したものなど）の重みを混ぜます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                RunSection(viewModel: viewModel, title: "混ぜる") { viewModel.merge() }
            }
        } result: {
            EmptyView()
        }
    }
}

// MARK: - 枝刈り

struct PruneView: View {
    @Bindable var viewModel: ForgeViewModel

    var body: some View {
        ForgeLayout(viewModel: viewModel) {
            Section {
                ModelPicker(title: "モデル", viewModel: viewModel, selection: $viewModel.pruneModel)
                TextField("取り除く層（例: 20, 21）", text: $viewModel.pruneLayers)
                TextField("0 にするヘッド（例: 3.5, 4.1 は「層.ヘッド」）", text: $viewModel.pruneHeads)
            } footer: {
                Text("層は 0 から数えます。「活性」や「Attention」で目星を付けてから抜き、「評価」で元のモデルとパープレキシティを比べると、どこが効いているかが分かります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RunSection(viewModel: viewModel, title: "枝を刈る") { viewModel.prune() }
        } result: {
            EmptyView()
        }
    }
}

// MARK: - 蒸留

struct DistillView: View {
    @Bindable var viewModel: ForgeViewModel

    var body: some View {
        ForgeLayout(viewModel: viewModel) {
            Section {
                ModelPicker(title: "先生", viewModel: viewModel, selection: $viewModel.teacher)
                ModelPicker(title: "生徒", viewModel: viewModel, selection: $viewModel.student)
                Picker("ノート", selection: $viewModel.distillFolder) {
                    Text("すべてのノート").tag("")
                    ForEach(viewModel.folders, id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                Text("先生の「次のトークンの確率分布」を、生徒に真似させます。先生と生徒は同じ語彙（同じ系列のモデル）が必要です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("設定") {
                Stepper(
                    "反復 \(viewModel.distillIterations) 回", value: $viewModel.distillIterations, in: 10...2000, step: 10)
                VStack(alignment: .leading) {
                    Text("温度 \(String(format: "%.1f", viewModel.distillTemperature))（分布をなだらかにして、2 番手以降の情報も渡す）")
                    Slider(value: $viewModel.distillTemperature, in: 1...5)
                }
                VStack(alignment: .leading) {
                    Text("先生に合わせる割合 \(String(format: "%.2f", viewModel.distillAlpha))")
                    Slider(value: $viewModel.distillAlpha, in: 0...1)
                }
                Picker("学習率", selection: $viewModel.distillLearningRate) {
                    ForEach(LabViewModel.learningRates, id: \.self) {
                        Text($0.formatted(.number.notation(.scientific))).tag($0)
                    }
                }
                Toggle("生徒に LoRA を付けて学習する（軽い）", isOn: $viewModel.distillUsesLoRA)
            }
            RunSection(viewModel: viewModel, title: "蒸留する") { viewModel.distill() }
        } result: {
            if !viewModel.trainingLoss.isEmpty {
                Text("損失").font(.headline)
                Chart(viewModel.trainingLoss) {
                    LineMark(x: .value("反復", $0.iteration), y: .value("損失", $0.loss))
                }
                .frame(minHeight: 200)
            }
        }
    }
}

// MARK: - 評価

struct EvaluateView: View {
    @Bindable var viewModel: ForgeViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("比べるモデル") {
                    ForEach(viewModel.models) { model in
                        Toggle(
                            model.name,
                            isOn: Binding(
                                get: { viewModel.evaluationModels.contains(model.id) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.evaluationModels.insert(model.id)
                                    } else {
                                        viewModel.evaluationModels.remove(model.id)
                                    }
                                }
                            )
                        )
                        .contextMenu {
                            if model.isLocal {
                                Button("このモデルを削除", role: .destructive) {
                                    Task { await viewModel.deleteLocalModel(model.id) }
                                }
                            }
                        }
                    }
                }
                Section {
                    Picker("測るノート", selection: $viewModel.evaluationFolder) {
                        Text("すべてのノート").tag("")
                        ForEach(viewModel.folders, id: \.self) { Text($0).tag($0) }
                    }
                    TextEditor(text: $viewModel.evaluationPrompts).frame(height: 60)
                } header: {
                    Text("ノートと、生成を比べるプロンプト（1 行に 1 つ）")
                } footer: {
                    Text("パープレキシティは、ノートの続きを当てる難しさです（小さいほどよい）。量子化や枝刈りでどれだけ悪くなったかが分かります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if viewModel.isRunning {
                        Button("止める", role: .destructive) { viewModel.cancel() }
                    } else {
                        Button("比べる") { viewModel.evaluate() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 380)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let progress = viewModel.progress {
                        ProgressBanner(title: progress.title, fraction: progress.fraction)
                    }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    if !viewModel.evaluationResults.isEmpty {
                        Chart(viewModel.evaluationResults) {
                            BarMark(x: .value("パープレキシティ", $0.perplexity), y: .value("モデル", $0.model))
                                .annotation(position: .trailing) { Text("") }
                        }
                        .frame(height: CGFloat(viewModel.evaluationResults.count) * 36 + 30)
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                            GridRow {
                                Text("モデル").fontWeight(.semibold)
                                Text("PPL").fontWeight(.semibold)
                                Text("速さ").fontWeight(.semibold)
                                Text("大きさ").fontWeight(.semibold)
                                Text("メモリ").fontWeight(.semibold)
                            }
                            ForEach(viewModel.evaluationResults) { result in
                                GridRow {
                                    Text(result.model).lineLimit(1)
                                    Text(result.perplexityText).monospacedDigit()
                                    Text(result.speed).monospacedDigit()
                                    Text(result.size)
                                    Text(result.memory)
                                }
                            }
                        }
                        .font(.callout)
                        ForEach(viewModel.evaluationResults) { result in
                            GroupBox(result.model) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(result.samples.enumerated()), id: \.offset) { _, sample in
                                        Text(sample).textSelection(.enabled).frame(
                                            maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    } else if viewModel.progress == nil {
                        ContentUnavailableView(
                            "評価", systemImage: "chart.xyaxis.line",
                            description: Text("元のモデルと、量子化・枝刈り・蒸留したモデルを、同じノートと同じプロンプトで比べます。"))
                    }
                }
                .padding(20)
            }
        }
    }
}
