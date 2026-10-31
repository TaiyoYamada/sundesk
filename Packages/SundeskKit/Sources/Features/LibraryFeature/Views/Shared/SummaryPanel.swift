//
//  SummaryPanel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI

/// オンデバイスのモデルで作る要約。
struct SummaryPanel: View {
    let viewModel: ReferenceDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                if let summary = viewModel.summary {
                    ForEach(summary.sections) { section in
                        InspectorSection(section.title) {
                            Text(section.body).textSelection(.enabled)
                        }
                    }
                    Text("Apple のオンデバイスモデルが \(summary.createdAt) に作った要約です。内容は PDF で確かめてください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if viewModel.summaryState == .idle {
                    Text(
                        viewModel.hasPDF
                            ? "PDF の本文を区切って読み、目的、手法、結果、限界にまとめます。"
                            : "要約するには、先に PDF を添付してください。"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.summaryState {
        case .running(let message):
            HStack {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
            buttons
        case .idle:
            buttons
        }
    }

    private var buttons: some View {
        HStack {
            Button(viewModel.summary == nil ? "要約する" : "作り直す", systemImage: "sparkles") {
                Task { await viewModel.makeSummary() }
            }
            .disabled(!viewModel.hasPDF)
            if viewModel.summary != nil {
                Button("メモに書き足す", systemImage: "text.badge.plus") { viewModel.appendSummaryToNote() }
            }
        }
    }
}
