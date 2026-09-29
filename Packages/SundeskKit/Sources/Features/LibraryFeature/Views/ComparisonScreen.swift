//
//  ComparisonScreen.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Charts
import SundeskDesignSystem
import SwiftUI

/// 実験を並べて比べるタブ。収束の曲線を重ね、指標と、値の違うパラメータを表にする。
public struct ComparisonScreen: View {
    @Bindable private var viewModel: ComparisonViewModel
    private let open: (_ key: String, _ title: String) -> Void

    /// - Parameter open: 実験を開く（キーと題名）。
    public init(viewModel: ComparisonViewModel, open: @escaping (_ key: String, _ title: String) -> Void) {
        self.viewModel = viewModel
        self.open = open
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("\(viewModel.rows.count) 件の実験を比べる").font(.title2.weight(.semibold))
                    Spacer()
                    Toggle("縦軸を最適値との差（対数）にする", isOn: $viewModel.logScaleY)
                        .disabled(viewModel.reference == nil)
                        .help("最適値が分かっているとき、収束の速さの違いが見やすくなる")
                }
                if viewModel.curves.isEmpty {
                    Text("曲線のある実験がありません。実験に結果の CSV を取り込むと、ここに重ねて描きます。")
                        .foregroundStyle(.secondary)
                } else {
                    chart.frame(height: 320)
                }
                metricsTable
                if !viewModel.differingParameters.isEmpty { parametersTable }
            }
            .padding(20)
        }
        .accessibilityIdentifier("comparison-screen")
        .task { await viewModel.load() }
    }

    private var chart: some View {
        Chart {
            ForEach(viewModel.curves) { curve in
                ForEach(Array(curve.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("x", point.x), y: .value("値", yValue(point.y)))
                        .foregroundStyle(by: .value("実験", curve.label))
                }
            }
            if let reference = viewModel.reference, !viewModel.logScaleY {
                RuleMark(y: .value("最適値", reference))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false), type: viewModel.logScaleY ? .log : .linear)
        .chartLegend(position: .bottom, alignment: .leading)
    }

    /// 対数のときは、最適値との差（0 にならないよう小さな値を足す）。
    private func yValue(_ value: Double) -> Double {
        guard viewModel.logScaleY, let reference = viewModel.reference else { return value }
        return max(abs(value - reference), 1e-12)
    }

    private var metricsTable: some View {
        InspectorSection("指標（最もよい値を強調）") {
            ScrollView(.horizontal) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("実験").fontWeight(.semibold)
                        Text("手法").fontWeight(.semibold)
                        ForEach(viewModel.metricNames, id: \.self) { Text($0).fontWeight(.semibold) }
                    }
                    ForEach(viewModel.rows) { row in
                        GridRow {
                            Button(row.title) { open(row.key, row.title) }.buttonStyle(.link).lineLimit(1)
                            Text(row.algorithm)
                            ForEach(Array(row.metrics.enumerated()), id: \.offset) { index, value in
                                Text(value)
                                    .monospacedDigit()
                                    .fontWeight(viewModel.isBest(row: row, metricIndex: index) ? .bold : .regular)
                                    .foregroundStyle(
                                        viewModel.isBest(row: row, metricIndex: index)
                                            ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            }
                        }
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
            }
        }
    }

    private var parametersTable: some View {
        InspectorSection("値の違うパラメータ") {
            ScrollView(.horizontal) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("実験").fontWeight(.semibold)
                        ForEach(viewModel.differingParameters, id: \.self) { Text($0).fontWeight(.semibold) }
                    }
                    ForEach(viewModel.rows) { row in
                        GridRow {
                            Text(row.title).lineLimit(1)
                            ForEach(Array(row.parameters.enumerated()), id: \.offset) { _, value in
                                Text(value).monospacedDigit()
                            }
                        }
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
            }
        }
    }
}
