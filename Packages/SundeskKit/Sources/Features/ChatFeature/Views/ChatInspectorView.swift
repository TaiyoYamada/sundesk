//
//  ChatInspectorView.swift
//  ChatFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SwiftUI

/// チャットのインスペクタ。最後の答えの出典を、本文の抜粋と一緒に出す。
public struct ChatInspectorView: View {
    private let viewModel: ChatViewModel
    private let openNote: (String, Int) -> Void

    public init(viewModel: ChatViewModel, openNote: @escaping (String, Int) -> Void) {
        self.viewModel = viewModel
        self.openNote = openNote
    }

    public var body: some View {
        let citations = viewModel.inspectedCitations
        if citations.isEmpty {
            ContentUnavailableView(
                "出典はまだありません", systemImage: "text.quote", description: Text("質問すると、根拠にしたノートの節をここに出します。"))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InspectorSection("出典（\(citations.count)）") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(citations) { citation in
                                Button {
                                    openNote(citation.path, citation.line)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text("[\(citation.number)]").monospacedDigit()
                                                .foregroundStyle(
                                                    citation.isCited ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                            Text(citation.title).fontWeight(.medium)
                                        }
                                        if !citation.heading.isEmpty {
                                            Text(citation.heading).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(citation.snippet).foregroundStyle(.secondary).lineLimit(4)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .opacity(citation.isCited ? 1 : 0.7)
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(14)
            }
        }
    }
}
