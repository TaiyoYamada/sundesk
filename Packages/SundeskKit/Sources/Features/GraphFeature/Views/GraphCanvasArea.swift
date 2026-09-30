//
//  GraphCanvasArea.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskGraphRenderer
import SwiftUI

/// グラフと、その上に重ねるもの（凡例、経路、時間の再生、出てくるノート、検索の候補、操作のヒント）。
struct GraphCanvasArea: View {
    let viewModel: GraphViewModel
    let canvas: GraphCanvasModel
    let suggestionIndex: Int
    let showsSuggestions: Bool
    let choose: (Int) -> Void

    @State private var width: CGFloat = 800

    var body: some View {
        ZStack {
            KnowledgeGraphView(model: canvas)
            GraphSourceCards(viewModel: viewModel, canvas: canvas, width: width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .overlay(alignment: .topLeading) {
            if showsSuggestions, !viewModel.searchSuggestions.isEmpty {
                GraphSearchSuggestions(
                    suggestions: viewModel.searchSuggestions, selection: suggestionIndex, choose: choose)
            }
        }
        .overlay(alignment: .top) {
            if !viewModel.path.isEmpty || viewModel.pathMessage != nil {
                GraphPathBar(viewModel: viewModel, canvas: canvas)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if canvas.timelineCursor == nil {
                GraphLegend(communities: viewModel.communities) { canvas.fly(toGroup: $0) }
            }
        }
        .overlay(alignment: .bottom) {
            if canvas.timelineCursor != nil {
                GraphTimelineBar(viewModel: viewModel, canvas: canvas)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.selected != nil, canvas.timelineCursor == nil {
                hint
            }
        }
    }

    private var hint: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("⇧ を押しながら押す: ここへの経路")
            Text("ダブルクリック・Return: ノートを開く")
            Text("矢印: 隣へ　Esc: 解除")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.regularMaterial.opacity(0.7), in: .rect(cornerRadius: 8))
        .padding(12)
        .allowsHitTesting(false)
    }
}

/// 凡例（まとまりの色と名前）。押すとそのまとまりへ飛ぶ。
struct GraphLegend: View {
    let communities: [CommunityItem]
    let fly: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(communities.prefix(8)) { community in
                Button {
                    fly(community.group)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(GraphColors.color(for: community.group)).frame(width: 8, height: 8)
                        Text(community.topLabels.joined(separator: "・"))
                            .lineLimit(1)
                        Text("\(community.size)")
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("このまとまりへ移る")
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .padding(12)
        .opacity(communities.isEmpty ? 0 : 1)
    }
}

/// 検索の候補。
struct GraphSearchSuggestions: View {
    let suggestions: [GraphNodeItem]
    let selection: Int
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Circle().fill(GraphColors.color(for: item.group)).frame(width: 8, height: 8)
                    Text(item.label).lineLimit(1)
                    Spacer(minLength: 0)
                    if index == selection {
                        Image(systemName: "return").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(index == selection ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
                .onTapGesture { choose(item.id) }
            }
        }
        .font(.callout)
        .padding(4)
        .frame(width: 260)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.leading, 12)
        .padding(.top, 6)
    }
}
