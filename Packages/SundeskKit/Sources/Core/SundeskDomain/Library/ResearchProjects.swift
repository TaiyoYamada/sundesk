//
//  ResearchProjects.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// ~/Research/experiment の 1 つのプロジェクト（git で管理している実験のリポジトリ）。読むだけ。
public struct ResearchProject: Hashable, Sendable, Identifiable {
    public var id: String { path }
    /// フォルダ名。
    public let name: String
    /// ライブラリの中でのパス（`Research/experiment/<name>`）。
    public let path: String
    /// README の最初の見出し（なければフォルダ名）。
    public let title: String
    /// README の最初の段落。
    public let summary: String?
    /// README と docs/ の Markdown（ライブラリの中でのパス）。
    public let documents: [String]
    /// 見つけた実行（新しい順）。
    public let runs: [ResearchRun]

    public init(
        name: String, path: String, title: String, summary: String?, documents: [String], runs: [ResearchRun]
    ) {
        self.name = name
        self.path = path
        self.title = title
        self.summary = summary
        self.documents = documents
        self.runs = runs
    }
}

/// プロジェクトの中で見つけた 1 回の実行（結果のフォルダ）。
///
/// `config.json` か CSV のあるフォルダを 1 回の実行とみなす（その下のフォルダは実行の一部）。
public struct ResearchRun: Hashable, Sendable, Identifiable {
    public var id: String { path }
    /// ライブラリの中でのパス（`Research/experiment/<project>/results/runs/<id>`）。
    public let path: String
    /// プロジェクトのフォルダ名。
    public let project: String
    /// プロジェクトの中での場所（`results/runs/2026-01-02_030405`）。
    public let relativePath: String
    /// 日時（フォルダ名から読めればそれ、なければ更新日時）。
    public let date: Date?
    /// config.json の設定（入れ子は `a.b` のように平らにする）。
    public let parameters: [String: ParameterValue]
    /// 表（CSV）。大きさの順ではなく名前順。
    public let tables: [ResearchFile]
    /// 図（PNG など。PDF の図は PNG と同じ名前があれば省く）。
    public let figures: [String]
    /// 所見などの Markdown（comments.md など）。
    public let notes: [String]

    public init(
        path: String, project: String, relativePath: String, date: Date?, parameters: [String: ParameterValue],
        tables: [ResearchFile], figures: [String], notes: [String]
    ) {
        self.path = path
        self.project = project
        self.relativePath = relativePath
        self.date = date
        self.parameters = parameters
        self.tables = tables
        self.figures = figures
        self.notes = notes
    }

    /// 一覧に出す名前（フォルダの最後の名前）。
    public var name: String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}

/// 実行の中のファイル。
public struct ResearchFile: Hashable, Sendable, Identifiable {
    public var id: String { path }
    /// ライブラリの中でのパス。
    public let path: String
    /// 実行のフォルダの中での名前（`tables/ablation.csv` など）。
    public let name: String
    public let size: Int

    public init(path: String, name: String, size: Int) {
        self.path = path
        self.name = name
        self.size = size
    }
}

/// 研究のデータ（~/Research）の実験を読む。
public protocol ResearchProjectRepository: Sendable {
    /// プロジェクトと、その実行を見つける。~/Research をつないでいなければ空。
    func projects() async -> [ResearchProject]
}

public protocol LoadResearchProjectsUseCase: Sendable {
    func callAsFunction() async -> [ResearchProject]
}

public struct LoadResearchProjectsInteractor: LoadResearchProjectsUseCase {
    private let repository: any ResearchProjectRepository

    public init(repository: any ResearchProjectRepository) {
        self.repository = repository
    }

    public func callAsFunction() async -> [ResearchProject] {
        await repository.projects()
    }
}

/// 表（CSV）の先頭。大きな表でも、最初の数行だけを読む。
public struct TableHead: Hashable, Sendable {
    public let columns: [String]
    public let rows: [[String]]
    /// ファイルの大きさ（バイト）。
    public let size: Int

    public init(columns: [String], rows: [[String]], size: Int) {
        self.columns = columns
        self.rows = rows
        self.size = size
    }
}

/// 表の先頭を読む。
public protocol ReadTableHeadUseCase: Sendable {
    /// - Parameters:
    ///   - path: ライブラリの中でのパス（つないだフォルダも含む）。
    ///   - rows: 読む行の数（見出しを除く）。
    func callAsFunction(path: String, rows: Int) async -> TableHead?
}
