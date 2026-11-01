//
//  LibraryWindowView.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// ライブラリのウインドウ。左のサイドバーでフォルダを選ぶと文献の一覧を、論文を選ぶとその PDF を、右の全部に出す。
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
                .navigationSplitViewColumnWidth(min: 220, ideal: 300, max: 480)
        } detail: {
            // 帯は右側にだけ出す（ウインドウ全体に出すと、サイドバーの上の行を隠す）
            detail.safeAreaInset(edge: .top, spacing: 0) { banners }
        }
        .searchable(text: $viewModel.query, placement: .toolbar, prompt: "題名、著者、年、タグ")
        // 論文を見ているときに検索を始めたら、その論文のあるフォルダの一覧に戻る
        .onChange(of: viewModel.query) { _, query in
            if !query.isEmpty { viewModel.returnToFolder() }
        }
        .toolbar { toolbar }
        .toolbar(removing: .title)
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
        if let id = viewModel.selectedReferenceID {
            ReferenceWorkspace(
                viewModel: dependencies.makeReader(id), tab: $inspectorTab, isInspectorPresented: $isInspectorPresented
            )
            .id(id)
        } else {
            ReferenceTable(viewModel: viewModel)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // ショートカットはメニューバー（AppFeature の LibraryCommands）にある
            Button("文献を足す", systemImage: "plus") { viewModel.isAddingIdentifier = true }
                .labelStyle(.titleAndIcon)
                .help("DOI、arXiv の ID、ISBN から文献を足す（⌘N）")
            Menu {
                Button("選んだ文献の BibTeX をコピー") { Task { await viewModel.copyBibTeX(for: viewModel.selection) } }
                    .disabled(viewModel.selection.isEmpty)
                Button("一覧の文献を書き出す…") { Task { await viewModel.exportVisibleRows() } }
                    .disabled(viewModel.rows.isEmpty)
            } label: {
                Label("BibTeX", systemImage: "curlybraces")
                    .labelStyle(.titleAndIcon)
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
            if let message = viewModel.noticeMessage {
                NoticeBanner(message: message) { viewModel.noticeMessage = nil }
            }
        }
    }

    private var isExporting: Binding<Bool> {
        Binding(get: { viewModel.exportText != nil }, set: { if !$0 { viewModel.exportText = nil } })
    }
}
