//
//  ExperimentScreen.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Charts
import SundeskDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// 実験のタブ。上に設定、指標、収束の曲線、図。下に仮説と考察のノート。
public struct ExperimentScreen<Note: View>: View {
    @Bindable private var viewModel: ExperimentViewModel
    private let note: Note
    private let openPath: (String) -> Void
    @State private var isAttaching = false

    /// - Parameters:
    ///   - note: 仮説と考察のエディタ（note.md）。
    ///   - openPath: つながる論文やデータを開く（ライブラリのルートからのパス）。
    public init(viewModel: ExperimentViewModel, openPath: @escaping (String) -> Void, @ViewBuilder note: () -> Note) {
        self.viewModel = viewModel
        self.openPath = openPath
        self.note = note()
    }

    public var body: some View {
        SplitPane(.vertical, fraction: 0.65, minFirst: 240, minSecond: 160) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    ForEach(viewModel.charts) { chart in
                        ConvergenceChart(chart: chart)
                    }
                    HStack(alignment: .top, spacing: 24) {
                        table("指標", viewModel.metrics)
                        table("パラメータ", viewModel.parameters)
                    }
                    if !viewModel.figures.isEmpty {
                        InspectorSection("図") {
                            ForEach(viewModel.figures, id: \.self) { url in
                                if let image = NSImage(contentsOf: url) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 720)
                                        .contextMenu {
                                            Button("Finder で表示") {
                                                NSWorkspace.shared.activateFileViewerSelecting([url])
                                            }
                                        }
                                }
                            }
                        }
                    }
                    if !viewModel.links.isEmpty || !viewModel.otherFiles.isEmpty {
                        InspectorSection("つながるもの") {
                            ForEach(viewModel.links, id: \.self) { link in
                                Button(link) { openPath(link) }.buttonStyle(.link)
                            }
                            ForEach(viewModel.otherFiles, id: \.self) { file in
                                Text(file).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await viewModel.attach(urls) }
                return true
            }
        } second: {
            note
        }
        .accessibilityIdentifier("experiment-screen")
        .task { await viewModel.load() }
        .fileImporter(
            isPresented: $isAttaching, allowedContentTypes: [.commaSeparatedText, .json, .image, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { Task { await viewModel.attach(urls) } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("名前", text: $viewModel.title)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit(save)
            HStack(spacing: 12) {
                Picker("アルゴリズム", selection: $viewModel.algorithm) {
                    ForEach(Set(ExperimentViewModel.algorithms + [viewModel.algorithm]).sorted(), id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .fixedSize()
                TextField("問題とインスタンス", text: $viewModel.problem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Picker("状態", selection: $viewModel.status) {
                    ForEach(ExperimentViewModel.statuses) { Text($0.value).tag($0.key) }
                }
                .fixedSize()
            }
            .onChange(of: viewModel.algorithm) { save() }
            .onChange(of: viewModel.status) { save() }
            HStack(spacing: 12) {
                if let objective = viewModel.objective { Label(objective, systemImage: "target") }
                if !viewModel.date.isEmpty { Label(viewModel.date, systemImage: "calendar") }
                Spacer()
                Button("結果を取り込む…", systemImage: "square.and.arrow.down") { isAttaching = true }
                    .help("CSV は収束の曲線に、画像は図になります（ここにドロップしても取り込めます）")
                if let folder = viewModel.folderURL {
                    Button("Finder で表示", systemImage: "folder") { NSWorkspace.shared.open(folder) }
                        .labelStyle(.iconOnly)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.orange).font(.callout)
            }
        }
    }

    private func table(_ title: String, _ rows: [KeyValueRow]) -> some View {
        InspectorSection(title) {
            if rows.isEmpty {
                Text("なし").foregroundStyle(.secondary).font(.callout)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.key).foregroundStyle(.secondary)
                            Text(row.value).monospacedDigit().textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
            }
        }
        .frame(minWidth: 200, alignment: .leading)
    }

    private func save() {
        Task { await viewModel.save() }
    }
}

/// 収束の曲線。
struct ConvergenceChart: View {
    let chart: ChartItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chart.file).font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(chart.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value(chart.xLabel, point.x), y: .value("値", point.y))
                        .foregroundStyle(by: .value("列", point.series))
                }
                if let reference = chart.reference {
                    RuleMark(y: .value("最適値", reference))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("最適値").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxisLabel(chart.xLabel)
            // 0 から描くと、Max-Cut の 600〜700 のような値の差がつぶれて見えない
            .chartYScale(domain: .automatic(includesZero: false))
            .rebuildsOnAppearanceChange()
            .frame(height: 220)
        }
    }
}
