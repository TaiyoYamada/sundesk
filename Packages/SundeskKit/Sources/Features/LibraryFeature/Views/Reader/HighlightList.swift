//
//  HighlightList.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// ハイライトとコメントの一覧。押すと PDF のその場所へ移る。
struct HighlightList: View {
    @Bindable var viewModel: ReaderViewModel

    var body: some View {
        if viewModel.highlights.isEmpty {
            ContentUnavailableView(
                "ハイライトがありません", systemImage: "highlighter",
                description: Text("PDF の文を選んで、ツールバーのハイライト（⇧⌘H）を押します。"))
        } else {
            List(selection: $viewModel.selectedHighlightID) {
                ForEach(viewModel.highlights) { highlight in
                    row(highlight)
                        .tag(highlight.id)
                        .contextMenu { menu(for: highlight) }
                }
            }
        }
    }

    private func row(_ highlight: HighlightDisplay) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(highlight.color.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.pageLabel).font(.caption).foregroundStyle(.secondary)
                Text(highlight.text).lineLimit(6)
                TextField(
                    "コメント",
                    text: Binding(
                        get: { highlight.comment }, set: { viewModel.setComment($0, for: highlight.id) }),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func menu(for highlight: HighlightDisplay) -> some View {
        Menu("色") {
            ForEach(HighlightColor.allCases) { color in
                Button(color.title) { Task { await viewModel.setColor(color, for: highlight.id) } }
            }
        }
        Button("メモに引用する") { viewModel.appendToNote(highlight.id) }
        Divider()
        Button("削除", role: .destructive) { Task { await viewModel.deleteHighlight(highlight.id) } }
    }
}
