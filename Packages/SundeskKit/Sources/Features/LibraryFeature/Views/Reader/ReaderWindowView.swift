//
//  ReaderWindowView.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// 1 件の文献の PDF を読むウインドウ。右のインスペクタに、注釈、メモ、要約を出す。
public struct ReaderWindowView: View {
    @State private var viewModel: ReaderViewModel
    @State private var controller = PDFReaderController()
    @State private var isInspectorPresented = true
    @State private var tab = DetailTab.annotations
    @State private var isAttaching = false

    public init(dependencies: LibraryDependencies, referenceID: UUID) {
        _viewModel = State(initialValue: dependencies.makeReader(referenceID))
    }

    public var body: some View {
        content
            .navigationTitle(viewModel.title)
            .inspector(isPresented: $isInspectorPresented) {
                inspector.inspectorColumnWidth(min: 260, ideal: 320, max: 520)
            }
            .toolbar { toolbar }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let message = viewModel.errorMessage ?? viewModel.detail.errorMessage {
                    ErrorBanner(message: message) {
                        viewModel.errorMessage = nil
                        viewModel.detail.errorMessage = nil
                    }
                }
            }
            .fileImporter(isPresented: $isAttaching, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result else { return }
                Task { await viewModel.attachPDF(url) }
            }
            .onChange(of: viewModel.selectedHighlightID) { _, id in
                if let highlight = viewModel.highlights.first(where: { $0.id == id }) { controller.reveal(highlight) }
            }
            .onAppear {
                controller.onHitHighlight = { id in
                    viewModel.selectedHighlightID = id
                    tab = .annotations
                    isInspectorPresented = true
                }
            }
            .task { await viewModel.start() }
            .task { await viewModel.detail.start() }
            .onDisappear {
                let detail = viewModel.detail
                Task { await detail.flush() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let url = viewModel.pdfURL {
            PDFReaderView(url: url, highlights: viewModel.highlights, controller: controller)
        } else {
            ContentUnavailableView {
                Label("PDF がありません", systemImage: "doc")
            } description: {
                Text("PDF を添付すると、ここで読めます。")
            } actions: {
                Button("PDF を添付…") { isAttaching = true }
            }
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $tab) {
                ForEach([DetailTab.annotations, .note, .summary]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch tab {
            case .annotations, .info: HighlightList(viewModel: viewModel)
            case .note: NoteEditor(viewModel: viewModel.detail)
            case .summary: SummaryPanel(viewModel: viewModel.detail)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("ハイライトの色", selection: $viewModel.color) {
                ForEach(HighlightColor.allCases) { color in
                    Label(color.title, systemImage: "circle.fill")
                        .foregroundStyle(color.color)
                        .tag(color)
                }
            }
            .pickerStyle(.menu)
            .help("ハイライトの色")
            Button("ハイライト", systemImage: "highlighter") { highlightSelection() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .help("選んだ文をハイライトする（⇧⌘H）")
                .disabled(viewModel.pdfURL == nil)
        }
        ToolbarItem {
            Button("インスペクタ", systemImage: "sidebar.trailing") { isInspectorPresented.toggle() }
                .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }

    private func highlightSelection() {
        guard let selection = controller.takeSelection() else { return }
        tab = .annotations
        isInspectorPresented = true
        Task { await viewModel.addHighlight(text: selection.text, rects: selection.rects) }
    }
}
