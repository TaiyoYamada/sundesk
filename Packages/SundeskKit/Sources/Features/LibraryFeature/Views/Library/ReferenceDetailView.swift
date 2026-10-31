//
//  ReferenceDetailView.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI

/// 一覧で選んだ 1 件の文献の、情報、メモ、要約。
struct ReferenceDetailView: View {
    @State private var viewModel: ReferenceDetailViewModel
    @State private var tab = DetailTab.info
    private let onOpenPDF: () -> Void

    init(viewModel: ReferenceDetailViewModel, onOpenPDF: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenPDF = onOpenPDF
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $tab) {
                ForEach([DetailTab.info, .note, .summary]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            if let draft = Binding($viewModel.draft) {
                switch tab {
                case .info, .annotations: ReferenceInfoForm(draft: draft, viewModel: viewModel, onOpenPDF: onOpenPDF)
                case .note: NoteEditor(viewModel: viewModel)
                case .summary: SummaryPanel(viewModel: viewModel)
                }
            } else {
                ContentUnavailableView("文献が見つかりません", systemImage: "questionmark.folder")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ErrorBanner(message: message) { viewModel.errorMessage = nil }
            }
        }
        .task { await viewModel.start() }
        .onDisappear {
            let viewModel = viewModel
            Task { await viewModel.flush() }
        }
    }
}
