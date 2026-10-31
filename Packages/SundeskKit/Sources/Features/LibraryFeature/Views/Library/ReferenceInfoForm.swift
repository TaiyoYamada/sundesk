//
//  ReferenceInfoForm.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 書誌情報、読んだ状態、タグを編集する。
struct ReferenceInfoForm: View {
    @Binding var draft: ReferenceDraft
    let viewModel: ReferenceDetailViewModel
    let onOpenPDF: () -> Void
    @State private var isAttaching = false

    var body: some View {
        Form {
            Section {
                Picker("種類", selection: $draft.type) {
                    ForEach(ReferenceTypeOption.allCases) { Text($0.title).tag($0) }
                }
                TextField("題名", text: $draft.title, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("reference-title")
                TextField("著者", text: $draft.authors, prompt: Text("1 行に 1 人（姓, 名）"), axis: .vertical)
                    .lineLimit(1...8)
                TextField("日付", text: $draft.date, prompt: Text("2014、2014-07、2014-07-23"))
                TextField(draft.type.containerLabel, text: $draft.containerTitle, axis: .vertical)
                TextField("巻", text: $draft.volume)
                TextField("号", text: $draft.issue)
                TextField("ページ", text: $draft.pages)
                TextField(draft.type.publisherLabel, text: $draft.publisher)
            }
            Section {
                TextField("DOI", text: $draft.doi)
                TextField("arXiv", text: $draft.arxiv)
                TextField("ISBN", text: $draft.isbn)
                TextField("URL", text: $draft.url)
                TextField("引用キー", text: $draft.citationKey, prompt: Text("空なら自動で付けます"))
            }
            Section {
                Picker("読んだ状態", selection: $draft.status) {
                    ForEach(ReadingStatusOption.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                LabeledContent("タグ") {
                    TagEditor(tags: draft.tags, onAdd: viewModel.addTag, onRemove: viewModel.removeTag)
                }
            }
            Section("要旨") {
                TextField("要旨", text: $draft.abstract, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(3...20)
            }
            Section {
                actions
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isAttaching, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await viewModel.attachPDF(url) }
        }
    }

    private var actions: some View {
        HStack {
            if viewModel.hasPDF {
                Button("PDF を開く", systemImage: "doc.richtext", action: onOpenPDF)
                Button("Finder で表示", systemImage: "folder") {
                    if let url = viewModel.pdfURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            Button(viewModel.hasPDF ? "PDF を差し替える…" : "PDF を添付…", systemImage: "paperclip") {
                isAttaching = true
            }
            Spacer()
            Button("書誌情報を取り直す", systemImage: "arrow.clockwise") {
                Task { await viewModel.refreshMetadata() }
            }
            .disabled(viewModel.isRefreshing || !hasIdentifier)
            .help("DOI、arXiv の ID、ISBN から、もう一度引きます")
        }
    }

    private var hasIdentifier: Bool {
        !(draft.doi + draft.arxiv + draft.isbn).trimmingCharacters(in: .whitespaces).isEmpty
    }
}
