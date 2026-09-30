//
//  InspectViews.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Charts
import SundeskDesignSystem
import SwiftUI

// MARK: - トークン

struct TokensView: View {
    let viewModel: LabViewModel

    var body: some View {
        if viewModel.tokens.isEmpty {
            LabPlaceholder(section: .tokens, description: "プロンプトが、モデルの語彙でどう区切られるかを見ます。")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(viewModel.tokens.count) トークン・\(viewModel.prompt.count) 文字")
                        .font(.callout).foregroundStyle(.secondary)
                    FlowLayout(spacing: 4) {
                        ForEach(viewModel.tokens) { token in
                            VStack(spacing: 2) {
                                Text(token.text).font(.system(size: 14, design: .monospaced))
                                Text("\(token.tokenID)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Heat.categorical(token.id).opacity(0.18), in: .rect(cornerRadius: 4))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 次のトークン

struct NextTokenView: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("温度")
                Slider(value: $viewModel.nextTokenTemperature, in: 0.1...2.0)
                    .frame(maxWidth: 220)
                Text(String(format: "%.2f", viewModel.nextTokenTemperature)).monospacedDigit()
                Spacer()
                if let entropy = viewModel.entropy {
                    Text("エントロピー \(String(format: "%.2f", entropy))").foregroundStyle(.secondary)
                        .help("分布の散らばり。大きいほど、次のトークンに迷っている")
                }
            }
            .onChange(of: viewModel.nextTokenTemperature) {
                if !viewModel.distribution.isEmpty { viewModel.run() }
            }
            if viewModel.distribution.isEmpty {
                LabPlaceholder(section: .nextToken, description: "プロンプトの続きに来るトークンの確率を、上位 20 個まで見ます。温度を変えると分布の形が変わります。")
            } else {
                Chart(viewModel.distribution) { item in
                    BarMark(x: .value("確率", item.probability), y: .value("トークン", item.text))
                        .annotation(position: .trailing) {
                            Text(String(format: "%.1f%%", item.probability * 100)).font(.caption).monospacedDigit()
                        }
                }
                .chartYAxis { AxisMarks { AxisValueLabel().font(.system(size: 12, design: .monospaced)) } }
                .chartXScale(domain: 0...1)
                .rebuildsOnAppearanceChange()
            }
        }
        .padding(20)
    }
}

// MARK: - 生成

struct GenerateView: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SamplingControls(viewModel: viewModel)
            if viewModel.generated.isEmpty {
                LabPlaceholder(
                    section: .generate,
                    description: "1 トークンずつ生成し、選ばれたトークンの確率で色を付けます。薄い色ほど、迷わず選ばれたトークンです。クリックすると、代わりの候補を出します。")
            } else {
                ScrollView {
                    FlowLayout(spacing: 0) {
                        ForEach(viewModel.generated) { token in
                            Text(token.text)
                                .font(.system(size: 14))
                                .padding(.vertical, 2)
                                .background(Heat.uncertainty(token.probability))
                                .overlay(alignment: .bottom) {
                                    if viewModel.selectedGeneratedIndex == token.id {
                                        Rectangle().fill(.tint).frame(height: 2)
                                    }
                                }
                                .onTapGesture { viewModel.selectedGeneratedIndex = token.id }
                                .help(String(format: "確率 %.1f%%", token.probability * 100))
                                .popover(isPresented: alternativesShown(token.id), arrowEdge: .bottom) {
                                    AlternativesView(token: token).frame(width: 240)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let speed = viewModel.tokensPerSecond {
                    Text(String(format: "%.1f トークン/秒", speed)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    /// トークンを押すと、代わりの候補をポップオーバーで出す。
    private func alternativesShown(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedGeneratedIndex == index },
            set: { if !$0, viewModel.selectedGeneratedIndex == index { viewModel.selectedGeneratedIndex = nil } }
        )
    }
}

struct SamplingControls: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("温度")
                    Slider(value: $viewModel.temperature, in: 0...2).frame(minWidth: 100, maxWidth: 220)
                    Text(String(format: "%.2f", viewModel.temperature)).monospacedDigit()
                }
                GridRow {
                    Text("top-p")
                    Slider(value: $viewModel.topP, in: 0.05...1).frame(minWidth: 100, maxWidth: 220)
                    Text(String(format: "%.2f", viewModel.topP)).monospacedDigit()
                }
            }
            FlowLayout(spacing: 12) {
                Stepper("最大 \(viewModel.maxTokens) トークン", value: $viewModel.maxTokens, in: 16...2048, step: 16)
                    .fixedSize()
                HStack(spacing: 6) {
                    Text("種")
                    TextField("毎回変える", value: $viewModel.seed, format: .number)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
                if !viewModel.adaptersForModel.isEmpty {
                    Picker("LoRA", selection: $viewModel.selectedAdapterID) {
                        Text("使わない").tag(UUID?.none)
                        ForEach(viewModel.adaptersForModel) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .fixedSize()
                }
            }
        }
        .font(.callout)
    }
}

private struct AlternativesView: View {
    let token: GeneratedTokenItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("「\(token.text)」の代わりの候補").font(.headline)
            Text(String(format: "選ばれた確率 %.1f%%", token.probability * 100)).foregroundStyle(.secondary)
            ForEach(token.alternatives) { alternative in
                HStack {
                    Text(alternative.text).font(.system(size: 13, design: .monospaced))
                    Spacer()
                    Text(String(format: "%.1f%%", alternative.probability * 100)).monospacedDigit()
                }
                ProgressView(value: alternative.probability)
            }
            Spacer()
        }
        .padding(14)
    }
}

// MARK: - Attention

struct AttentionView: View {
    @Bindable var viewModel: LabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attention = viewModel.attention {
                HStack(spacing: 16) {
                    Stepper(
                        "層 \(viewModel.attentionLayer + 1) / \(attention.layerCount)",
                        onIncrement: {
                            viewModel.showAttention(layer: min(viewModel.attentionLayer + 1, attention.layerCount - 1))
                        },
                        onDecrement: { viewModel.showAttention(layer: max(viewModel.attentionLayer - 1, 0)) }
                    )
                    Picker("ヘッド", selection: $viewModel.attentionHead) {
                        Text("平均").tag(Int?.none)
                        ForEach(0..<attention.headCount, id: \.self) { Text("\($0 + 1)").tag(Int?.some($0)) }
                    }
                    .fixedSize()
                    Spacer()
                }
                Text("行のトークンが、列のトークンをどれだけ見ているか").font(.caption).foregroundStyle(.secondary)
                HeatmapView(
                    matrix: attention.matrix(head: viewModel.attentionHead), rowLabels: attention.tokens,
                    columnLabels: attention.tokens, maxValue: 1)
            } else {
                LabPlaceholder(section: .attention, description: "各層・各ヘッドで、トークンがどのトークンに注目しているかを行列で見ます。")
            }
        }
        .padding(20)
    }
}

// MARK: - Logit lens

struct LogitLensView: View {
    let viewModel: LabViewModel

    var body: some View {
        if let lens = viewModel.lens {
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        Text("層").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(lens.tokens.enumerated()), id: \.offset) { _, token in
                            Text(token).font(.system(size: 11, design: .monospaced)).lineLimit(1).frame(width: 64)
                        }
                    }
                    ForEach(Array(lens.cells.enumerated().reversed()), id: \.offset) { layer, row in
                        GridRow {
                            Text("\(layer + 1)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(width: 64, height: 20)
                                    .background(Heat.intensity(cell.probability), in: .rect(cornerRadius: 2))
                                    .help(String(format: "「%@」%.1f%%", cell.text, cell.probability * 100))
                            }
                        }
                    }
                }
                .padding(20)
            }
        } else {
            LabPlaceholder(section: .logitLens, description: "途中の層の状態を、そのまま最後の出力層に通すと何を予測するかを見ます。上ほど後ろの層です。")
        }
    }
}

// MARK: - 活性

struct ActivationsView: View {
    let viewModel: LabViewModel

    var body: some View {
        if let activations = viewModel.activations {
            VStack(alignment: .leading, spacing: 8) {
                Text("残差ストリームの大きさ（L2 ノルム）。行が層、列がトークン").font(.caption).foregroundStyle(.secondary)
                HeatmapView(
                    matrix: activations.norms, rowLabels: activations.norms.indices.map { "\($0 + 1)" },
                    columnLabels: activations.tokens, maxValue: activations.maxNorm)
            }
            .padding(20)
        } else {
            LabPlaceholder(section: .activations, description: "各層・各トークンの活性の大きさを見ます。")
        }
    }
}

// MARK: - 補助

/// 行列を色の濃さで描く。
struct HeatmapView: View {
    let matrix: [[Double]]
    let rowLabels: [String]
    let columnLabels: [String]
    let maxValue: Double
    @State private var hovered: (row: Int, column: Int)?

    private var cell: CGFloat {
        let count = max(matrix.count, matrix.first?.count ?? 0)
        return count > 40 ? 12 : count > 20 ? 18 : 26
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Color.clear.frame(height: 70)
                        ForEach(Array(rowLabels.enumerated()), id: \.offset) { _, label in
                            Text(label).font(.system(size: 10, design: .monospaced)).lineLimit(1).frame(height: cell)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(columnLabels.enumerated()), id: \.offset) { _, label in
                                Text(label).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                                    .fixedSize()
                                    .rotationEffect(.degrees(-60), anchor: .bottomLeading)
                                    .frame(width: cell, height: 70, alignment: .bottomLeading)
                            }
                        }
                        Canvas { context, _ in
                            for (row, values) in matrix.enumerated() {
                                for (column, value) in values.enumerated() {
                                    let rect = CGRect(
                                        x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell - 1,
                                        height: cell - 1)
                                    context.fill(Path(rect), with: .color(Heat.intensity(value / max(maxValue, 1e-9))))
                                }
                            }
                        }
                        .frame(width: CGFloat(matrix.first?.count ?? 0) * cell, height: CGFloat(matrix.count) * cell)
                        .onContinuousHover { phase in
                            if case .active(let point) = phase {
                                hovered = (Int(point.y / cell), Int(point.x / cell))
                            } else {
                                hovered = nil
                            }
                        }
                    }
                }
                .padding(4)
            }
            if let hovered, matrix.indices.contains(hovered.row), matrix[hovered.row].indices.contains(hovered.column) {
                Text(
                    "\(rowLabels[safe: hovered.row] ?? "") → \(columnLabels[safe: hovered.column] ?? ""): "
                        + String(format: "%.4f", matrix[hovered.row][hovered.column])
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// 値を色にする。
enum Heat {
    static func intensity(_ value: Double) -> Color {
        Color.accentColor.opacity(0.08 + 0.92 * min(max(value, 0), 1))
    }

    /// 確率の低い（迷った）トークンほど濃くする。
    static func uncertainty(_ probability: Double) -> Color {
        Color.orange.opacity(0.55 * (1 - min(max(probability, 0), 1)))
    }

    static func categorical(_ index: Int) -> Color {
        [Color.blue, .orange, .green, .pink, .purple, .teal][index % 6]
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
