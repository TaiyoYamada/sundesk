//
//  TuningViews.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Charts
import SundeskDesignSystem
import SwiftUI

// MARK: - LoRA

struct LoRAView: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        AdaptiveSplit(settingsWidth: 340) {
            Form {
                Section("学習に使うノート") {
                    Picker("フォルダ", selection: $viewModel.loraFolder) {
                        Text("すべてのノート").tag("")
                        ForEach(viewModel.folders, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("名前", text: $viewModel.loraName)
                }
                Section("設定") {
                    Stepper(
                        "反復 \(viewModel.loraIterations) 回", value: $viewModel.loraIterations, in: 10...2000, step: 10)
                    Stepper("ランク \(viewModel.loraRank)", value: $viewModel.loraRank, in: 2...64, step: 2)
                    Stepper("層の数 \(viewModel.loraLayers)", value: $viewModel.loraLayers, in: 1...32)
                    Picker("学習率", selection: $viewModel.loraLearningRate) {
                        ForEach(LabViewModel.learningRates, id: \.self) {
                            Text($0.formatted(.number.notation(.scientific))).tag($0)
                        }
                    }
                }
                Section {
                    if viewModel.isRunning {
                        Button("止める", role: .destructive) { viewModel.cancel() }
                    } else {
                        Button("学習を始める") { viewModel.run() }
                            .buttonStyle(.borderedProminent)
                    }
                } footer: {
                    Text("ノートの本文を「続きを書く」形で学習し、ノートの書き方や言葉づかいをモデルに覚えさせます。16GB では 0.6B〜1.7B のモデルが現実的です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } result: {
            VStack(alignment: .leading, spacing: 16) {
                Text("損失").font(.headline)
                if viewModel.trainingLoss.isEmpty {
                    Text("学習を始めると、損失の変化をここに描きます。").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(viewModel.trainingLoss) {
                            LineMark(
                                x: .value("反復", $0.iteration), y: .value("損失", $0.loss), series: .value("種類", "学習")
                            )
                            .foregroundStyle(by: .value("種類", "学習"))
                        }
                        ForEach(viewModel.validationLoss) {
                            PointMark(x: .value("反復", $0.iteration), y: .value("損失", $0.loss))
                                .foregroundStyle(by: .value("種類", "検証"))
                        }
                    }
                    .frame(minHeight: 200)
                    .rebuildsOnAppearanceChange()
                }
                Text("できた LoRA").font(.headline)
                if viewModel.adapters.isEmpty {
                    Text("まだありません。「生成」でモデルと一緒に選ぶと、効き目を試せます。").foregroundStyle(.secondary)
                } else {
                    List(viewModel.adapters) { adapter in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adapter.name).fontWeight(.medium)
                            Text(adapter.model).font(.caption).foregroundStyle(.secondary)
                            Text(adapter.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button("削除", role: .destructive) { Task { await viewModel.deleteAdapter(adapter.id) } }
                        }
                    }
                    .frame(minHeight: 160)
                }
                Spacer()
            }
            .padding(20)
        }
    }
}

// MARK: - Steering

struct SteeringView: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        AdaptiveSplit(settingsWidth: 340) {
            Form {
                Section {
                    Stepper("層 \(viewModel.steeringLayer)", value: $viewModel.steeringLayer, in: 0...80)
                    VStack(alignment: .leading) {
                        Text("強さ \(String(format: "%.1f", viewModel.steeringStrength))")
                        Slider(value: $viewModel.steeringStrength, in: -12...12)
                    }
                    SamplingControlsCompact(viewModel: viewModel)
                }
                Section("向かわせたい文（1 行に 1 つ）") {
                    TextEditor(text: $viewModel.steeringPositive).frame(height: 70)
                }
                Section {
                    TextEditor(text: $viewModel.steeringNegative).frame(height: 70)
                } header: {
                    Text("遠ざけたい文（1 行に 1 つ）")
                } footer: {
                    Text("2 組の文で、指定した層の活性の平均の差をとり、それを生成中の活性に足します。強さを負にすると逆向きになります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } result: {
            if let steering = viewModel.steering {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        comparison("そのまま", steering.baseline)
                        comparison("steering あり（ベクトルの大きさ \(steering.norm)）", steering.steered)
                    }
                    .frame(minWidth: 480)
                    VStack(alignment: .leading, spacing: 16) {
                        comparison("そのまま", steering.baseline)
                        comparison("steering あり（ベクトルの大きさ \(steering.norm)）", steering.steered)
                    }
                }
                .padding(20)
            } else {
                LabPlaceholder(section: .steering, description: "同じ種で、ベクトルを足さない生成と足した生成を並べて比べます。")
            }
        }
    }

    private func comparison(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView {
                Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SamplingControlsCompact: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        Stepper("最大 \(viewModel.maxTokens) トークン", value: $viewModel.maxTokens, in: 16...1024, step: 16)
        VStack(alignment: .leading) {
            Text("温度 \(String(format: "%.2f", viewModel.temperature))")
            Slider(value: $viewModel.temperature, in: 0...1.5)
        }
    }
}
