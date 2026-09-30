//
//  GraphOverlays.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskGraphRenderer
import SwiftUI

/// 経路（たどる順の概念）。押すとその概念へ飛ぶ。
struct GraphPathBar: View {
    let viewModel: GraphViewModel
    let canvas: GraphCanvasModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(.secondary)
            if let message = viewModel.pathMessage {
                Text(message).foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.path.enumerated()), id: \.element.id) { index, step in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button {
                        canvas.fly(toNode: step.id)
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(GraphColors.color(for: step.group)).frame(width: 7, height: 7)
                            Text(step.label).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("「\(step.label)」へ移る")
                }
                Text("\(viewModel.path.count - 1) 歩")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 4)
            }
            Button("経路を消す", systemImage: "xmark.circle.fill") { viewModel.clearPath() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("経路を消す（Esc）")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .frame(maxWidth: 760)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 育つ様子の再生（ノートを作った順）。
struct GraphTimelineBar: View {
    let viewModel: GraphViewModel
    let canvas: GraphCanvasModel

    var body: some View {
        let cursor = canvas.timelineCursor ?? 1
        let steps = viewModel.timeline
        let step = steps.isEmpty ? nil : steps[min(Int((cursor * Double(steps.count - 1)).rounded()), steps.count - 1)]
        HStack(spacing: 12) {
            Button(
                canvas.isPlayingTimeline ? "止める" : "再生",
                systemImage: canvas.isPlayingTimeline ? "pause.fill" : "play.fill"
            ) {
                if canvas.isPlayingTimeline { canvas.pauseTimeline() } else { canvas.playTimeline() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.title3)
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(step?.date ?? "").font(.callout.weight(.semibold)).monospacedDigit()
                    Text(step?.title ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Slider(value: Binding(get: { cursor }, set: { canvas.setTimelineCursor($0) }))
                    .controlSize(.small)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(canvas.visibleNodeCount)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(viewModel.nodes.count) 概念").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 70, alignment: .trailing)
            Button("再生を閉じる", systemImage: "xmark.circle.fill") { canvas.closeTimeline() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("再生を閉じて、すべてを表示する")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 620)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 4)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }
}

/// 選んだ概念のそばに出す、出てくるノート（近づいたときだけ）。押すとノートを開く。
struct GraphSourceCards: View {
    let viewModel: GraphViewModel
    let canvas: GraphCanvasModel
    let width: CGFloat

    var body: some View {
        if let anchor = canvas.selectionAnchor, canvas.noteDetail > 0.01, let concept = viewModel.selected,
            !concept.sources.isEmpty
        {
            let offset = canvas.selectionRadius + 20 + 140
            let onLeft = anchor.x + offset + 140 > width
            VStack(alignment: .leading, spacing: 6) {
                Text("出てくるノート").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(concept.sources.prefix(4)) { source in
                    Button {
                        viewModel.noteOpener?(source.path, source.line)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.heading.isEmpty ? source.title : "\(source.title) › \(source.heading)")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.tint)
                                .lineLimit(1)
                            Text(source.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.6)))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("このノートを開く")
                }
            }
            .frame(width: 280)
            .opacity(canvas.noteDetail)
            .scaleEffect(0.94 + 0.06 * canvas.noteDetail, anchor: onLeft ? .trailing : .leading)
            .position(x: min(max(anchor.x + (onLeft ? -offset : offset), 150), max(width - 150, 150)), y: anchor.y)
            .allowsHitTesting(canvas.noteDetail > 0.5)
        }
    }
}
