//
//  GraphScreen.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SundeskGraphRenderer
import SwiftUI

/// 知識グラフのタブ。
public struct GraphScreen: View {
    @Bindable private var viewModel: GraphViewModel
    @State private var canvas = GraphCanvasModel()

    public init(viewModel: GraphViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let build = viewModel.build {
                ProgressBanner(title: build.title, fraction: build.fraction)
                Divider()
            }
            if let error = viewModel.buildError {
                ErrorBanner(message: error) { viewModel.buildError = nil }
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { canvas.onSelect = { id in Task { await viewModel.select(conceptID: id) } } }
        .onChange(of: viewModel.nodes, initial: true) { applyScene() }
        .onChange(of: viewModel.edges) { applyScene() }
        .onChange(of: viewModel.matchingNodeIDs, initial: true) { _, ids in canvas.highlightedNodeIDs = ids }
        .onChange(of: viewModel.selected?.id) { _, id in canvas.select(nodeID: id) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .empty:
            ContentUnavailableView {
                Label("知識グラフはまだありません", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text("ノートから用語と関係を抜き出して、グラフを作ります。初回はエンジンの準備とモデルのダウンロードに時間がかかります。")
            } actions: {
                Button("ノートから作る") { Task { await viewModel.rebuild() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.build != nil)
            }
        case .ready:
            KnowledgeGraphView(model: canvas)
                .overlay(alignment: .bottomLeading) { legend }
        case .failed(let message):
            ContentUnavailableView(
                "知識グラフを読めませんでした", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TextField("概念を探す", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit {
                    if let first = viewModel.matchingNodeIDs.first {
                        canvas.focus(on: first)
                        Task { await viewModel.select(conceptID: first) }
                    }
                }
            Picker("表示する概念", selection: $viewModel.nodeLimit) {
                ForEach(GraphViewModel.nodeLimits, id: \.self) { Text("上位 \($0)").tag($0) }
            }
            .fixedSize()
            Text(viewModel.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("全体を表示", systemImage: "arrow.up.left.and.arrow.down.right") { canvas.fitAll() }
                .help("全体を表示")
            Button("配置し直す", systemImage: "wind") { canvas.reheat() }
                .help("点の配置をもう一度計算する")
            Button("作り直す", systemImage: "arrow.clockwise") { Task { await viewModel.rebuild() } }
                .help("ノートから知識グラフを作り直す")
                .disabled(viewModel.build != nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.communities.prefix(8)) { community in
                HStack(spacing: 6) {
                    Circle().fill(GraphColors.color(for: community.id)).frame(width: 8, height: 8)
                    Text(community.topLabels.joined(separator: "・"))
                        .lineLimit(1)
                }
            }
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .padding(12)
        .opacity(viewModel.communities.isEmpty ? 0 : 1)
    }

    private func applyScene() {
        canvas.setScene(
            GraphScene(
                nodes: viewModel.nodes.map {
                    GraphScene.Node(id: $0.id, label: $0.label, radius: Float($0.radius), group: $0.community)
                },
                edges: viewModel.edges.map {
                    GraphScene.Edge(source: $0.source, target: $0.target, weight: Float($0.weight))
                }
            ))
    }
}
