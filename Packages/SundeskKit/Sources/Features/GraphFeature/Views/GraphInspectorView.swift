//
//  GraphInspectorView.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SundeskGraphRenderer
import SwiftUI

/// 知識グラフのインスペクタ。選んだ概念の隣と、出てくるノートの節。経路をたどっているときは、その道。
public struct GraphInspectorView: View {
    private let viewModel: GraphViewModel
    private let openNote: (String, Int) -> Void

    /// - Parameter openNote: 出どころを押したとき（ノートのパス、行番号）。グラフのダブルクリックでも使う。
    public init(viewModel: GraphViewModel, openNote: @escaping (String, Int) -> Void) {
        self.viewModel = viewModel
        self.openNote = openNote
    }

    public var body: some View {
        Group {
            if let concept = viewModel.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        InspectorSection("概念") {
                            HStack(spacing: 8) {
                                Circle().fill(GraphColors.color(for: concept.group)).frame(width: 10, height: 10)
                                Text(concept.label).font(.title3.weight(.semibold)).textSelection(.enabled)
                            }
                            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                                GridRow {
                                    Text("重要度").foregroundStyle(.secondary)
                                    Text(concept.importance).monospacedDigit()
                                }
                                GridRow {
                                    Text("出現").foregroundStyle(.secondary)
                                    Text("\(concept.frequency) 回")
                                }
                            }
                            .font(.callout)
                        }
                        if !viewModel.path.isEmpty {
                            pathSection
                        }
                        relatedSection(concept)
                        sourcesSection(concept)
                    }
                    .padding(14)
                }
            } else {
                ContentUnavailableView(
                    "概念を選んでください", systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("グラフの点を押すと、つながる概念と、出てくるノートを表示します。⇧ を押しながら別の点を押すと、経路をたどります。"))
            }
        }
        .onAppear { if viewModel.noteOpener == nil { viewModel.noteOpener = openNote } }
    }

    private var pathSection: some View {
        InspectorSection("経路（\(viewModel.path.count - 1) 歩）") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(viewModel.path.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 6) {
                        Text("\(index + 1)").foregroundStyle(.tertiary).monospacedDigit().frame(width: 18)
                        Circle().fill(GraphColors.color(for: step.group)).frame(width: 7, height: 7)
                        Text(step.label)
                    }
                }
            }
            .font(.callout)
        }
    }

    private func relatedSection(_ concept: ConceptDetailItem) -> some View {
        InspectorSection("つながる概念（\(concept.related.count)）") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(concept.related) { related in
                    Button {
                        Task { await viewModel.select(conceptID: related.id) }
                    } label: {
                        HStack {
                            Text(related.label)
                            Spacer()
                            Text(related.kinds).foregroundStyle(.secondary).font(.caption)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
        }
    }

    private func sourcesSection(_ concept: ConceptDetailItem) -> some View {
        InspectorSection("出てくるノート（\(concept.sources.count)）") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(concept.sources) { source in
                    Button {
                        openNote(source.path, source.line)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.heading.isEmpty ? source.title : "\(source.title) › \(source.heading)")
                                .foregroundStyle(.tint)
                            Text(source.snippet).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
        }
    }
}
