//
//  LibraryNavigatorView.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI
import UniformTypeIdentifiers

/// ライブラリで開くもの。
public enum LibraryDestination: Hashable, Sendable {
    /// ノートやファイル（ライブラリのルートからのパス）。
    case file(String)
    case paper(key: String, title: String)
    case experiment(key: String, title: String)
    case comparison(keys: [String])
    /// ~/Research のプロジェクト（ライブラリの中でのパス）。
    case researchProject(path: String, title: String)
    /// ~/Research の 1 回の実行（ライブラリの中でのパス）。
    case researchRun(path: String, title: String)
}

/// 研究ライブラリの一覧。上で種類を切り替え、下にその種類のファイルの木を出す。
///
/// どの種類も、フォルダでくくれるファイルの木（ノートと同じ）。論文、実験、~/Research の実行は、フォルダを 1 つのものとして見せる。
public struct LibraryNavigatorView<Tree: View>: View {
    @Bindable private var viewModel: LibraryViewModel
    private let tree: (LibraryViewModel.Section) -> Tree
    private let open: (LibraryDestination) -> Void

    @State private var sheet: Sheet?
    @State private var importing: [UTType]?

    private enum Sheet: Identifiable {
        case paper, note, experiment
        var id: Self { self }
    }

    /// - Parameters:
    ///   - tree: 種類ごとのファイルの木。
    ///   - open: 選んだものを開く（足したものを開くときにも使う）。
    public init(
        viewModel: LibraryViewModel, @ViewBuilder tree: @escaping (LibraryViewModel.Section) -> Tree,
        open: @escaping (LibraryDestination) -> Void
    ) {
        self.viewModel = viewModel
        self.tree = tree
        self.open = open
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if let message = viewModel.errorMessage {
                Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal, 10).padding(.bottom, 4)
                    .textSelection(.enabled)
            } else if let message = viewModel.message {
                HStack(spacing: 6) {
                    if viewModel.isWorking { ProgressView().controlSize(.mini) }
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            tree(viewModel.section)
                .id(viewModel.section)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) { compareButton }
                .dropDestination(for: URL.self) { urls, _ in
                    Task { await drop(urls) }
                    return true
                }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .paper: AddPaperSheet(viewModel: viewModel) { if let key = $0 { openPaper(key) } }
            case .note: NewNoteSheet(viewModel: viewModel) { if let path = $0 { open(.file(path)) } }
            case .experiment: NewExperimentSheet(viewModel: viewModel) { if let key = $0 { openExperiment(key) } }
            }
        }
        .fileImporter(
            isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
            allowedContentTypes: importing ?? [.item], allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await drop(urls) }
        }
        .task { await viewModel.observe() }
        .onChange(of: viewModel.section) { Task { await viewModel.sectionChanged() } }
    }

    /// 実験を 2 つ以上選んだら、比べるボタンを出す。
    @ViewBuilder
    private var compareButton: some View {
        let keys = viewModel.selectedExperimentKeys
        if viewModel.section == .experiments, keys.count >= 2 {
            Button("選んだ \(keys.count) 件を比べる", systemImage: "chart.xyaxis.line") {
                open(.comparison(keys: keys))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.bottom, 44)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Picker("種類", selection: $viewModel.section) {
                ForEach(LibraryViewModel.Section.allCases) { section in
                    Image(systemName: section.systemImage).help(section.title).accessibilityLabel(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("library-section")
            addMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var addMenu: some View {
        Menu {
            switch viewModel.section {
            case .notes:
                Button("新しいノート…") { sheet = .note }
            case .papers:
                Button("arXiv・DOI から足す…") { sheet = .paper }
                Button("PDF を取り込む…") { importing = [.pdf] }
            case .experiments:
                Button("新しい実験…") { sheet = .experiment }
            case .data, .materials:
                Button("ファイルを取り込む…") { importing = [.item] }
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("足す")
        .accessibilityIdentifier("library-add")
    }

    private func openPaper(_ key: String) {
        let title = viewModel.papers.first { $0.key == key }?.title ?? key
        open(.paper(key: key, title: title))
    }

    private func openExperiment(_ key: String) {
        let title = viewModel.experiments.first { $0.key == key }?.title ?? key
        open(.experiment(key: key, title: title))
    }

    private func drop(_ urls: [URL]) async {
        switch viewModel.section {
        case .papers:
            if let key = await viewModel.importPapers(urls.filter { $0.pathExtension.lowercased() == "pdf" }) {
                openPaper(key)
            }
        case .data, .materials, .notes:
            await viewModel.importFiles(urls)
        case .experiments:
            break
        }
    }
}
