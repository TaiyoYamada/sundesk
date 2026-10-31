//
//  ReferenceWorkspace.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// 一覧で選んだ文献の PDF と、右のインスペクタ（情報、注釈、メモ、要約）。
struct ReferenceWorkspace: View {
    @State private var viewModel: ReaderViewModel
    @State private var controller = PDFReaderController()
    @State private var isAttaching = false
    @Binding private var tab: DetailTab
    @Binding private var isInspectorPresented: Bool

    init(viewModel: ReaderViewModel, tab: Binding<DetailTab>, isInspectorPresented: Binding<Bool>) {
        _viewModel = State(initialValue: viewModel)
        _tab = tab
        _isInspectorPresented = isInspectorPresented
    }

    var body: some View {
        content
            .inspector(isPresented: $isInspectorPresented) {
                inspector.inspectorColumnWidth(min: 280, ideal: 360, max: 560)
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
                ForEach(DetailTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            // 中身が短いタブ（ハイライトがないときの案内）でも、タブの切り替えを上に留めるため、高さいっぱいに広げる
            Group {
                switch tab {
                case .info: ReferenceInfoTab(viewModel: viewModel.detail)
                case .annotations: HighlightList(viewModel: viewModel)
                case .note: NoteEditor(viewModel: viewModel.detail)
                case .summary: SummaryPanel(viewModel: viewModel.detail)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button("インスペクタ", systemImage: "sidebar.trailing") { isInspectorPresented.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("情報、注釈、メモ、要約を出す（⌥⌘I）")
        }
    }

    private func highlightSelection() {
        guard let selection = controller.takeSelection() else { return }
        tab = .annotations
        isInspectorPresented = true
        Task { await viewModel.addHighlight(text: selection.text, rects: selection.rects) }
    }
}
