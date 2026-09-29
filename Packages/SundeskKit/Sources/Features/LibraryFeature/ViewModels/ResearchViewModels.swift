//
//  ResearchViewModels.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import Observation
import SundeskDomain

/// ~/Research の画面の ViewModel を作る（ワークスペースに渡す）。
public struct ResearchScreenFactory {
    public let makeProject: (String) -> ResearchProjectViewModel
    public let makeRun: (String) -> ResearchRunViewModel

    public init(
        makeProject: @escaping (String) -> ResearchProjectViewModel, makeRun: @escaping (String) -> ResearchRunViewModel
    ) {
        self.makeProject = makeProject
        self.makeRun = makeRun
    }
}

/// ~/Research の 1 つのプロジェクト。README と、見つけた実行の一覧。
@MainActor
@Observable
public final class ResearchProjectViewModel {
    public let path: String
    public private(set) var title = ""
    public private(set) var summary: String?
    public private(set) var documents: [String] = []
    /// 実行を、置き場所（`results/lab` など）ごとにまとめたもの。
    public private(set) var groups: [ResearchRunGroup] = []
    public private(set) var isLoaded = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let loadProjects: any LoadResearchProjectsUseCase

    public init(path: String, loadProjects: any LoadResearchProjectsUseCase) {
        self.path = path
        self.loadProjects = loadProjects
    }

    /// README のパス（なければ nil）。
    public var readmePath: String? {
        documents.first { $0.hasSuffix("/README.md") }
    }

    public func load() async {
        guard let project = await loadProjects().first(where: { $0.path == path }) else {
            errorMessage = "プロジェクトが見つかりません（\(path)）"
            return
        }
        title = project.title
        summary = project.summary
        documents = project.documents
        groups = ResearchRunGroup.grouping(project.runs)
        isLoaded = true
    }
}

/// 置き場所ごとの実行。
public struct ResearchRunGroup: Identifiable, Hashable, Sendable {
    public var id: String { folder }
    /// プロジェクトの中での置き場所（`results/runs` など）。
    public let folder: String
    public let runs: [ResearchRunRow]

    static func grouping(_ runs: [ResearchRun]) -> [ResearchRunGroup] {
        var order: [String] = []
        var byFolder: [String: [ResearchRunRow]] = [:]
        for run in runs {
            let folder = (run.relativePath as NSString).deletingLastPathComponent
            if byFolder[folder] == nil { order.append(folder) }
            byFolder[folder, default: []].append(ResearchRunRow(run))
        }
        return order.map { ResearchRunGroup(folder: $0.isEmpty ? "（直下）" : $0, runs: byFolder[$0] ?? []) }
    }
}

/// 一覧の 1 行（実行）。
public struct ResearchRunRow: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let date: String
    /// 「表 5・図 20」のような中身の要約。
    public let detail: String

    public init(_ run: ResearchRun) {
        path = run.path
        name = run.name
        date = run.date?.formatted(date: .abbreviated, time: .shortened) ?? ""
        var parts: [String] = []
        if !run.tables.isEmpty { parts.append("表 \(run.tables.count)") }
        if !run.figures.isEmpty { parts.append("図 \(run.figures.count)") }
        if !run.notes.isEmpty { parts.append("所見 \(run.notes.count)") }
        detail = parts.joined(separator: "・")
    }
}

/// ~/Research の 1 回の実行。設定、所見、図、表を見る（読むだけ）。
@MainActor
@Observable
public final class ResearchRunViewModel {
    public let path: String
    public private(set) var projectTitle = ""
    public private(set) var projectPath = ""
    public private(set) var name = ""
    public private(set) var relativePath = ""
    public private(set) var date = ""
    public private(set) var parameters: [KeyValueRow] = []
    public private(set) var tables: [TableFileRow] = []
    public private(set) var figures: [FigureItem] = []
    public private(set) var notes: [String] = []
    public private(set) var errorMessage: String?
    /// 選んでいる表（先頭を見せる）。
    public var selectedTable: String? {
        didSet {
            guard selectedTable != oldValue else { return }
            Task { await loadHead() }
        }
    }
    public private(set) var head: TableHeadItem?

    @ObservationIgnored private let loadProjects: any LoadResearchProjectsUseCase
    @ObservationIgnored private let readHead: any ReadTableHeadUseCase
    @ObservationIgnored private let fileURL: (String) -> URL

    public init(
        path: String, loadProjects: any LoadResearchProjectsUseCase, readHead: any ReadTableHeadUseCase,
        fileURL: @escaping (String) -> URL
    ) {
        self.path = path
        self.loadProjects = loadProjects
        self.readHead = readHead
        self.fileURL = fileURL
    }

    /// 実行のフォルダ（Finder で開く）。
    public var folderURL: URL { fileURL(path) }

    public func load() async {
        let projects = await loadProjects()
        guard let project = projects.first(where: { path.hasPrefix($0.path + "/") }),
            let run = project.runs.first(where: { $0.path == path })
        else {
            errorMessage = "実行が見つかりません（\(path)）"
            return
        }
        projectTitle = project.title
        projectPath = project.path
        name = run.name
        relativePath = run.relativePath
        date = run.date?.formatted(date: .abbreviated, time: .shortened) ?? ""
        parameters = run.parameters.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { KeyValueRow(key: $0.key, value: $0.value.description) }
        tables = run.tables.map(TableFileRow.init)
        figures = run.figures.map { FigureItem(path: $0, url: fileURL($0)) }
        notes = run.notes
        if selectedTable == nil { selectedTable = Self.preferredTable(run.tables)?.path }
    }

    /// 最初に見せる表（まとめの表を優先する）。
    static func preferredTable(_ tables: [ResearchFile]) -> ResearchFile? {
        for name in ["summary.csv", "results.csv"] {
            if let table = tables.first(where: { $0.name == name }) { return table }
        }
        return tables.min { $0.size < $1.size }
    }

    private func loadHead() async {
        guard let selectedTable else {
            head = nil
            return
        }
        head = await readHead(path: selectedTable, rows: 200).map(TableHeadItem.init)
    }
}

public struct TableFileRow: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let size: String

    init(_ file: ResearchFile) {
        path = file.path
        name = file.name
        size = ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
    }
}

public struct FigureItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let url: URL

    public var name: String { url.lastPathComponent }
}

/// 表の先頭（見せる用）。
public struct TableHeadItem: Hashable, Sendable {
    public let columns: [String]
    public let rows: [[String]]
    public let size: String

    init(_ head: TableHead) {
        columns = head.columns
        rows = head.rows.map { row in
            // 列が足りない行は空で埋める
            row.count >= head.columns.count ? row : row + Array(repeating: "", count: head.columns.count - row.count)
        }
        size = ByteCountFormatter.string(fromByteCount: Int64(head.size), countStyle: .file)
    }
}
