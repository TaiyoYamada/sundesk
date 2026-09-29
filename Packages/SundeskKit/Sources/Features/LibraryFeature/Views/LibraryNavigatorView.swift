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
}

/// 研究ライブラリの一覧。上で種類を切り替え、下に一覧を出す。
public struct LibraryNavigatorView<Notes: View>: View {
    @Bindable private var viewModel: LibraryViewModel
    private let selectedPath: String?
    private let notes: Notes
    private let open: (LibraryDestination) -> Void

    @State private var sheet: Sheet?
    @State private var importing: [UTType]?

    private enum Sheet: Identifiable {
        case paper, note, experiment
        var id: Self { self }
    }

    /// - Parameters:
    ///   - selectedPath: 今開いているもののフォルダかパス（一覧の選択と連動させる）。
    ///   - notes: ノートの一覧（ファイルの木）。
    ///   - open: 選んだものを開く。
    public init(
        viewModel: LibraryViewModel, selectedPath: String?, @ViewBuilder notes: () -> Notes,
        open: @escaping (LibraryDestination) -> Void
    ) {
        self.viewModel = viewModel
        self.selectedPath = selectedPath
        self.notes = notes()
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
            content
                .frame(maxHeight: .infinity)
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.section {
        case .notes:
            notes
        case .papers:
            PaperListView(viewModel: viewModel, selectedPath: selectedPath, open: openPaper)
        case .experiments:
            ExperimentListView(viewModel: viewModel, selectedPath: selectedPath, open: openExperiment) { keys in
                open(.comparison(keys: keys))
            }
        case .data, .materials:
            FileListView(viewModel: viewModel, selectedPath: selectedPath) { open(.file($0)) }
        }
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

// MARK: - 一覧

private struct PaperListView: View {
    @Bindable var viewModel: LibraryViewModel
    let selectedPath: String?
    let open: (String) -> Void

    var body: some View {
        List(selection: Binding(get: { selectedKey }, set: { if let key = $0 { open(key) } })) {
            ForEach(viewModel.shownPapers) { paper in
                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title).lineLimit(2)
                    HStack(spacing: 4) {
                        Text([paper.authors, paper.year.map(String.init)].compactMap { $0 }.joined(separator: "・"))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if paper.hasPDF { Image(systemName: "doc.richtext").help("PDF あり") }
                        StatusBadge(text: paper.status, isStrong: paper.status == "読書中")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(paper.key)
                .contextMenu {
                    Button("ゴミ箱に入れる", role: .destructive) { Task { await viewModel.delete(paper.folderPath) } }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("paper-list")
        .overlay {
            if viewModel.papers.isEmpty {
                ContentUnavailableView(
                    "論文はまだありません", systemImage: "doc.text.magnifyingglass",
                    description: Text("＋ から arXiv や DOI で足すか、PDF をここにドロップします。"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            FilterBar(text: $viewModel.filterText) {
                Menu {
                    Picker("並べ替え", selection: $viewModel.paperSort) {
                        ForEach(LibraryViewModel.PaperSort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("読んだ状態", selection: $viewModel.statusFilter) {
                        Text("すべて").tag(String?.none)
                        ForEach(LibraryViewModel.statuses, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var selectedKey: String? {
        viewModel.papers.first { selectedPath?.hasPrefix($0.folderPath) == true }?.key
    }
}

private struct ExperimentListView: View {
    @Bindable var viewModel: LibraryViewModel
    let selectedPath: String?
    let open: (String) -> Void
    let compare: ([String]) -> Void

    var body: some View {
        List(selection: $viewModel.selectedExperiments) {
            ForEach(viewModel.shownExperiments) { experiment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(experiment.title).lineLimit(2)
                    HStack(spacing: 4) {
                        Text(experiment.algorithm).fontWeight(.medium)
                        Text(experiment.problem).lineLimit(1)
                        Spacer(minLength: 0)
                        StatusBadge(text: experiment.status, isStrong: !experiment.isDone)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let headline = experiment.headline {
                        Text(headline).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .tag(experiment.key)
                .contextMenu {
                    Button("開く") { open(experiment.key) }
                    Button("ゴミ箱に入れる", role: .destructive) { Task { await viewModel.delete(experiment.folderPath) } }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("experiment-list")
        .onChange(of: viewModel.selectedExperiments) { _, keys in
            if keys.count == 1, let key = keys.first { open(key) }
        }
        .overlay {
            if viewModel.experiments.isEmpty {
                ContentUnavailableView(
                    "実験はまだありません", systemImage: "testtube.2",
                    description: Text("＋ から作るか、記録用ライブラリ（sundesk-log）で実験のコードから送ります。"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if viewModel.selectedExperiments.count >= 2 {
                    Button("選んだ \(viewModel.selectedExperiments.count) 件を比べる", systemImage: "chart.xyaxis.line") {
                        compare(viewModel.shownExperiments.map(\.key).filter(viewModel.selectedExperiments.contains))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(6)
                }
                FilterBar(text: $viewModel.filterText) { EmptyView() }
            }
        }
    }
}

private struct FileListView: View {
    @Bindable var viewModel: LibraryViewModel
    let selectedPath: String?
    let open: (String) -> Void

    var body: some View {
        List(selection: Binding(get: { selectedPath }, set: { if let path = $0 { open(path) } })) {
            ForEach(viewModel.shownFiles) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Label(file.name, systemImage: file.systemImage).lineLimit(1)
                    Text(file.detail).font(.caption).foregroundStyle(.secondary)
                }
                .tag(file.path)
                .contextMenu {
                    Button("ゴミ箱に入れる", role: .destructive) { Task { await viewModel.delete(file.path) } }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("file-list")
        .overlay {
            if viewModel.files.isEmpty {
                ContentUnavailableView(
                    "\(viewModel.section.title)はまだありません", systemImage: viewModel.section.systemImage,
                    description: Text("ファイルをここにドロップするか、＋ から取り込みます。"))
            }
        }
        .safeAreaInset(edge: .bottom) { FilterBar(text: $viewModel.filterText) { EmptyView() } }
    }
}

private struct FilterBar<Accessory: View>: View {
    @Binding var text: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
            TextField("絞り込む", text: $text).textFieldStyle(.plain)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

struct StatusBadge: View {
    let text: String
    let isStrong: Bool

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(isStrong ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary), in: .capsule)
    }
}
