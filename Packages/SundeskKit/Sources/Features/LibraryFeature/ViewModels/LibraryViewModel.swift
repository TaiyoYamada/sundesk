//
//  LibraryViewModel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 研究ライブラリの一覧（左のナビゲータ）。種類を切り替え、取り込み、新しく作る。
@MainActor
@Observable
public final class LibraryViewModel {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case notes, papers, experiments, data, materials

        public var id: Self { self }

        public var title: String {
            switch self {
            case .notes: "ノート"
            case .papers: "論文"
            case .experiments: "実験"
            case .data: "データ"
            case .materials: "資料"
            }
        }

        public var systemImage: String {
            switch self {
            case .notes: "note.text"
            case .papers: "doc.text.magnifyingglass"
            case .experiments: "testtube.2"
            case .data: "tablecells"
            case .materials: "photo.on.rectangle"
            }
        }

        /// ライブラリのルートからのフォルダ。
        public var folder: String { domain.folder }

        var domain: LibrarySection {
            switch self {
            case .notes: .notes
            case .papers: .papers
            case .experiments: .experiments
            case .data: .data
            case .materials: .materials
            }
        }
    }

    public enum PaperSort: String, CaseIterable, Identifiable, Sendable {
        case added, year, title

        public var id: Self { self }
        public var title: String {
            switch self {
            case .added: "追加した順"
            case .year: "年"
            case .title: "題名"
            }
        }
    }

    public var section: Section = .notes
    public var filterText = ""
    public var paperSort: PaperSort = .added
    /// 読んだ状態で絞り込む（nil ならすべて）。
    public var statusFilter: String?
    /// 比べるために選んだ実験。
    public var selectedExperiments: Set<String> = []

    public private(set) var papers: [PaperRow] = []
    public private(set) var experiments: [ExperimentRow] = []
    public private(set) var files: [FileRow] = []
    public private(set) var isWorking = false
    public var message: String?
    public var errorMessage: String?

    public static let statuses = ReadingStatus.allCases.map(\.rawValue)

    @ObservationIgnored private let library: any ManageLibraryUseCase
    @ObservationIgnored private let observeChanges: any ObserveVaultChangesUseCase
    @ObservationIgnored private var paperModels: [Paper] = []

    public init(library: any ManageLibraryUseCase, observeChanges: any ObserveVaultChangesUseCase) {
        self.library = library
        self.observeChanges = observeChanges
    }

    // MARK: - 読み込み

    /// 一覧を読み、ライブラリが変わるたびに読み直す（取り込み箱も見る）。
    public func observe() async {
        try? await library.prepare()
        await refresh()
        for await _ in observeChanges() {
            await refresh()
        }
    }

    public func refresh() async {
        if let imported = try? await library.importInbox(), !imported.isEmpty {
            message = "取り込み箱から \(imported.count) 件の実験を取り込みました"
        }
        paperModels = (try? await library.papers()) ?? []
        papers = paperModels.map(PaperRow.init)
        experiments = ((try? await library.experiments()) ?? []).map(ExperimentRow.init)
        switch section {
        case .data, .materials: files = ((try? await library.files(in: section.domain)) ?? []).map(FileRow.init)
        default: break
        }
    }

    public func sectionChanged() async {
        filterText = ""
        await refresh()
    }

    /// 絞り込み、並べ替えた論文。
    public var shownPapers: [PaperRow] {
        var rows = papers.filter { row in
            (statusFilter == nil || row.status == statusFilter)
                && (filterText.isEmpty || row.searchText.localizedStandardContains(filterText))
        }
        switch paperSort {
        case .added: break
        case .year: rows.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .title: rows.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return rows
    }

    public var shownExperiments: [ExperimentRow] {
        experiments.filter { filterText.isEmpty || $0.searchText.localizedStandardContains(filterText) }
    }

    public var shownFiles: [FileRow] {
        files.filter { filterText.isEmpty || $0.path.localizedStandardContains(filterText) }
    }

    // MARK: - 足す

    /// arXiv の ID か DOI（URL でもよい）から論文を足す。足した論文のキーを返す。
    public func addPaper(identifier text: String, downloadsPDF: Bool) async -> String? {
        guard let identifier = PaperIdentifier(parsing: text) else {
            errorMessage = "arXiv の ID（1304.3061 など）か DOI（10.1038/… など）を入れてください"
            return nil
        }
        return await work("書誌情報を取っています") {
            try await self.library.addPaper(identifier: identifier, downloadsPDF: downloadsPDF).key
        }
    }

    /// PDF を取り込んで論文にする。最後に取り込んだ論文のキーを返す。
    public func importPapers(_ urls: [URL]) async -> String? {
        let key: String?? = await work("PDF を取り込んでいます") {
            var last: String?
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                last = try await self.library.importPaper(pdf: url).key
            }
            return last
        }
        return key.flatMap { $0 }
    }

    public func createNote(named name: String) async -> String? {
        await work(nil) { try await self.library.createNote(named: name) }
    }

    public func createExperiment(title: String, algorithm: String, problem: String) async -> String? {
        await work(nil) {
            try await self.library.createExperiment(title: title, algorithm: algorithm, problem: problem).key
        }
    }

    /// データや資料のファイルを取り込む。
    public func importFiles(_ urls: [URL]) async {
        _ = await work("取り込んでいます") {
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                _ = try await self.library.importFiles([url], into: self.section.domain)
            }
            return ""
        }
    }

    public func delete(_ path: String) async {
        _ = await work(nil) {
            try await self.library.delete(path)
            return ""
        }
    }

    private func work<T>(_ title: String?, _ body: @escaping () async throws -> T) async -> T? {
        isWorking = true
        errorMessage = nil
        message = title
        defer {
            isWorking = false
            if let title, message == title { message = nil }
        }
        do {
            let result = try await body()
            await refresh()
            return result
        } catch let error as LibraryError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }
}

// MARK: - 表示用の型

public struct PaperRow: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let authors: String
    public let year: Int?
    public let status: String
    public let hasPDF: Bool
    public let tags: [String]
    /// 論文のフォルダ（タブで開くときに使う）。
    public let folderPath: String
    var searchText: String { [title, authors, tags.joined(separator: " ")].joined(separator: " ") }

    init(_ paper: Paper) {
        key = paper.key
        title = paper.metadata.title
        let names = paper.metadata.authors.map { $0.split(separator: " ").last.map(String.init) ?? $0 }
        authors = names.count > 3 ? names.prefix(3).joined(separator: ", ") + " ほか" : names.joined(separator: ", ")
        year = paper.metadata.year
        status = paper.status.rawValue
        hasPDF = paper.pdfPath != nil
        tags = paper.tags
        folderPath = "\(LibrarySection.papers.folder)/\(paper.key)"
    }
}

public struct ExperimentRow: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let algorithm: String
    public let problem: String
    public let status: String
    public let isDone: Bool
    public let date: String
    /// 目的関数の値（あれば）。
    public let headline: String?
    public let folderPath: String
    var searchText: String { [title, algorithm, problem].joined(separator: " ") }

    init(_ experiment: ResearchExperiment) {
        key = experiment.key
        title = experiment.title
        algorithm = experiment.algorithm
        problem = experiment.problem
        status = experiment.status.title
        isDone = experiment.status == .done
        date = experiment.created?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let best = experiment.metrics.first { $0.key.hasPrefix("best") } ?? experiment.metrics.first
        headline = best.map { "\($0.key) \(ExperimentFormat.number($0.value))" }
        folderPath = experiment.folderPath
    }
}

public struct FileRow: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let detail: String
    public let systemImage: String

    init(_ file: LibraryFile) {
        path = file.path
        name = file.name
        detail =
            ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            + "・" + file.modified.formatted(date: .abbreviated, time: .omitted)
        let kind = FileKind(fileName: file.name)
        systemImage =
            switch kind {
            case .code: "chevron.left.forwardslash.chevron.right"
            case .image: "photo"
            case .pdf: "doc.richtext"
            case .markdown: "doc.text"
            case .text: "doc.plaintext"
            default: "doc"
            }
    }
}

enum ExperimentFormat {
    static func number(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 { return String(Int64(value)) }
        return abs(value) >= 1e4 || abs(value) < 1e-3 ? String(format: "%.4g", value) : String(format: "%.4f", value)
    }
}
