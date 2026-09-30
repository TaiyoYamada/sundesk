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

/// PDF の、このページを開いてほしいという頼み。同じページでも、頼むたびに移る。
public struct PDFPageRequest: Equatable, Sendable {
    /// 1 から数えたページ。
    public let page: Int
    private let id = UUID()

    public init(page: Int) {
        self.page = page
    }
}

/// 論文のタブ。左に PDF、右に書誌情報と論文メモ。
public struct PaperScreen<Note: View>: View {
    @Bindable private var viewModel: PaperViewModel
    private let pageRequest: PDFPageRequest?
    private let note: Note
    @State private var isAttaching = false

    /// - Parameters:
    ///   - pageRequest: PDF のこのページを開く（チャットの出典から開いたときなど）。
    ///   - note: 論文メモのエディタ（note.md）。
    public init(viewModel: PaperViewModel, pageRequest: PDFPageRequest? = nil, @ViewBuilder note: () -> Note) {
        self.viewModel = viewModel
        self.pageRequest = pageRequest
        self.note = note()
    }

    public var body: some View {
        SplitPane(.horizontal, fraction: 0.55, minFirst: 320, minSecond: 320) {
            pdf
        } second: {
            SplitPane(.vertical, fraction: 0.4, minFirst: 160, minSecond: 200) {
                ScrollView { details.padding(14) }
            } second: {
                note
            }
        }
        .accessibilityIdentifier("paper-screen")
        .task { await viewModel.load() }
        .fileImporter(isPresented: $isAttaching, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { Task { await viewModel.attachPDF(url) } }
        }
    }

    @ViewBuilder
    private var pdf: some View {
        if let url = viewModel.pdfURL {
            PDFKitView(url: url, pageRequest: pageRequest)
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
            FlowLayout(spacing: 12) {
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
            TextField(label, text: text, prompt: Text("なし"))
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
    let pageRequest: PDFPageRequest?

    final class Coordinator {
        var handledRequest: PDFPageRequest?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        guard let pageRequest, context.coordinator.handledRequest != pageRequest,
            let page = view.document?.page(at: pageRequest.page - 1)
        else { return }
        context.coordinator.handledRequest = pageRequest
        view.go(to: page)
    }
}
