//
//  PaperScreen.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import PDFKit
import SundeskDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// 論文のタブ。左に PDF、右に書誌情報と論文メモ。
public struct PaperScreen<Note: View>: View {
    @Bindable private var viewModel: PaperViewModel
    private let note: Note
    @State private var isAttaching = false

    /// - Parameter note: 論文メモのエディタ（note.md）。
    public init(viewModel: PaperViewModel, @ViewBuilder note: () -> Note) {
        self.viewModel = viewModel
        self.note = note()
    }

    public var body: some View {
        HSplitView {
            pdf
                .frame(minWidth: 320, idealWidth: 560)
            VSplitView {
                ScrollView { details.padding(14) }
                    .frame(minHeight: 160, idealHeight: 260)
                note
                    .frame(minHeight: 200)
            }
            .frame(minWidth: 320, idealWidth: 420)
        }
        .task { await viewModel.load() }
        .fileImporter(isPresented: $isAttaching, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { Task { await viewModel.attachPDF(url) } }
        }
    }

    @ViewBuilder
    private var pdf: some View {
        if let url = viewModel.pdfURL {
            PDFKitView(url: url)
        } else {
            ContentUnavailableView {
                Label("PDF はありません", systemImage: "doc.richtext")
            } description: {
                Text("手元の PDF を添付すると、ここで読めます。")
            } actions: {
                Button("PDF を添付…") { isAttaching = true }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
                Task { await viewModel.attachPDF(url) }
                return true
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("題名", text: $viewModel.title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit(save)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                field("著者", $viewModel.authors)
                field("年", $viewModel.year)
                field("雑誌・会議", $viewModel.venue)
                field("arXiv", $viewModel.arxiv)
                field("DOI", $viewModel.doi)
                field("タグ", $viewModel.tags)
                GridRow {
                    Text("状態").foregroundStyle(.secondary)
                    Picker("状態", selection: $viewModel.status) {
                        ForEach(LibraryViewModel.statuses, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: viewModel.status) { save() }
                }
            }
            .font(.callout)
            HStack {
                Button("書誌情報を取り直す", systemImage: "arrow.clockwise") { Task { await viewModel.refresh() } }
                    .disabled(viewModel.isWorking || (viewModel.arxiv.isEmpty && viewModel.doi.isEmpty))
                Button("BibTeX をコピー", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.bibtex, forType: .string)
                }
                if let url = URL(string: viewModel.url), !viewModel.url.isEmpty {
                    Link(destination: url) { Label("開く", systemImage: "safari") }
                }
                if viewModel.pdfURL == nil {
                    Button("PDF を添付", systemImage: "paperclip") { isAttaching = true }
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            if let error = viewModel.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .labelsHidden()
                .onSubmit(save)
        }
    }

    private func save() {
        Task { await viewModel.save() }
    }
}

/// PDFKit の表示。
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
