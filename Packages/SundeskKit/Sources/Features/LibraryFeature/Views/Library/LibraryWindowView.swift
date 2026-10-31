//
//  LibraryWindowView.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// ライブラリのウインドウ（サイドバー、文献の一覧、選んだ文献の詳細）。
public struct LibraryWindowView: View {
    private let dependencies: LibraryDependencies
    @State private var viewModel: LibraryViewModel
    @AppStorage("inspector.tab") private var inspectorTab = DetailTab.info
    @AppStorage("inspector.isPresented") private var isInspectorPresented = true

    public init(dependencies: LibraryDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: dependencies.makeLibrary())
    }

    public var body: some View {
        NavigationSplitView {
            LibrarySidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            ReferenceTable(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 460)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 480, ideal: 760)
        }
        .searchable(text: $viewModel.query, placement: .toolbar, prompt: "題名、著者、年、タグ")
        .toolbar { toolbar }
        .safeAreaInset(edge: .top, spacing: 0) { banners }
        .focusedSceneValue(viewModel)
        .task { await viewModel.start() }
        .sheet(isPresented: $viewModel.isAddingIdentifier) {
            AddIdentifierSheet { await viewModel.add(identifier: $0) }
        }
        .fileImporter(
            isPresented: $viewModel.isImportingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await viewModel.importPDFs(urls) }
        }
        .fileExporter(
            isPresented: isExporting, document: viewModel.exportText.map(BibTeXFile.init),
            contentType: BibTeXFile.contentType, defaultFilename: viewModel.exportFileName
        ) { result in
            if case .failure(let error) = result { viewModel.errorMessage = error.localizedDescription }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if viewModel.selection.count == 1, let id = viewModel.selection.first {
            ReferenceWorkspace(
                viewModel: dependencies.makeReader(id), tab: $inspectorTab, isInspectorPresented: $isInspectorPresented
            )
            .id(id)
        } else {
            ContentUnavailableView(
                viewModel.selection.isEmpty ? "文献を選んでください" : "\(viewModel.selection.count) 件を選んでいます",
                systemImage: "doc.text")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // ショートカットはメニューバー（AppFeature の LibraryCommands）にある
            Button("文献を足す", systemImage: "plus") { viewModel.isAddingIdentifier = true }
                .help("DOI、arXiv の ID、ISBN から文献を足す（⌘N）")
            Menu {
                Button("選んだ文献の BibTeX をコピー") { Task { await viewModel.copyBibTeX(for: viewModel.selection) } }
                    .disabled(viewModel.selection.isEmpty)
                Button("一覧の文献を書き出す…") { Task { await viewModel.exportVisibleRows() } }
                    .disabled(viewModel.rows.isEmpty)
            } label: {
                Label("BibTeX", systemImage: "curlybraces")
            }
            .help("BibTeX を書き出す")
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 0) {
            if let message = viewModel.progressMessage {
                ProgressBanner(title: message, fraction: nil)
            }
            if let message = viewModel.errorMessage {
                ErrorBanner(message: message) { viewModel.errorMessage = nil }
            }
        }
    }

    private var isExporting: Binding<Bool> {
        Binding(get: { viewModel.exportText != nil }, set: { if !$0 { viewModel.exportText = nil } })
    }
}
