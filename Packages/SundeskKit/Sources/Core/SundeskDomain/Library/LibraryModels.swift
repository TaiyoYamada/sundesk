//
//  LibraryModels.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 研究ライブラリの種類（左のナビゲータの一覧）。形式は docs/library-format.md。
public enum LibrarySection: String, CaseIterable, Sendable {
    case notes
    case papers
    case experiments
    case data
    case materials

    /// ライブラリのルートからのフォルダ名。
    public var folder: String {
        switch self {
        case .notes: "Notes"
        case .papers: "Papers"
        case .experiments: "Experiments"
        case .data: "Data"
        case .materials: "Materials"
        }
    }

    /// 取り込み箱のフォルダ名。
    public static let inboxFolder = "Inbox"
}

// MARK: - 論文

public enum ReadingStatus: String, CaseIterable, Sendable {
    case unread = "未読"
    case reading = "読書中"
    case read = "読了"
}

/// 論文の書誌情報。
public struct PaperMetadata: Hashable, Sendable {
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var arxiv: String?
    public var doi: String?
    public var url: String?
    public var abstract: String?

    public init(
        title: String, authors: [String] = [], year: Int? = nil, venue: String? = nil, arxiv: String? = nil,
        doi: String? = nil, url: String? = nil, abstract: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.arxiv = arxiv
        self.doi = doi
        self.url = url
        self.abstract = abstract
    }
}

/// ライブラリの論文（`Papers/<キー>/`）。
public struct Paper: Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public var metadata: PaperMetadata
    public var status: ReadingStatus
    public var tags: [String]
    public var added: Date?
    /// 論文メモ（`Papers/<キー>/note.md`）の、ライブラリのルートからのパス。
    public var notePath: String { "\(LibrarySection.papers.folder)/\(key)/note.md" }
    /// 本文の PDF（なければ nil）。
    public let pdfPath: String?

    public init(
        key: String, metadata: PaperMetadata, status: ReadingStatus, tags: [String], added: Date?, pdfPath: String?
    ) {
        self.key = key
        self.metadata = metadata
        self.status = status
        self.tags = tags
        self.added = added
        self.pdfPath = pdfPath
    }
}

/// 論文の識別子（arXiv か DOI）。
public enum PaperIdentifier: Hashable, Sendable {
    case arxiv(String)
    case doi(String)

    /// 入力された文字（URL、`arXiv:` 付き、DOI の URL など）から読み取る。arXiv の DOI は arXiv として扱う。
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.firstMatch(of: /(10\.\d{4,9}\/[^\s"<>]+)/) {
            var doi = String(match.output.1)
            while let last = doi.last, ".,;)".contains(last) { doi.removeLast() }
            if let arxiv = doi.firstMatch(of: /(?i)arxiv\.(\d{4}\.\d{4,5})/) {
                self = .arxiv(String(arxiv.output.1))
            } else {
                self = .doi(doi)
            }
        } else if let match = trimmed.firstMatch(of: /(\d{4}\.\d{4,5})(?:v\d+)?/) {
            self = .arxiv(String(match.output.1))
        } else {
            return nil
        }
    }
}

// MARK: - 実験

public enum ExperimentStatus: String, CaseIterable, Sendable {
    case planned
    case running
    case done
    case failed

    public var title: String {
        switch self {
        case .planned: "予定"
        case .running: "実行中"
        case .done: "完了"
        case .failed: "失敗"
        }
    }
}

/// パラメータの値（文字、数、真偽）。
public enum ParameterValue: Hashable, Sendable, CustomStringConvertible {
    case text(String)
    case number(Double)
    case flag(Bool)

    public var description: String {
        switch self {
        case .text(let text): text
        case .number(let number):
            if number == number.rounded() && abs(number) < 1e15 {
                String(Int64(number))
            } else {
                String(number)
            }
        case .flag(let flag): flag ? "true" : "false"
        }
    }
}

/// 目的関数。
public struct Objective: Hashable, Sendable {
    public var name: String
    /// true なら小さいほどよい。
    public var minimizes: Bool
    /// 分かっている最適値。
    public var reference: Double?

    public init(name: String, minimizes: Bool, reference: Double?) {
        self.name = name
        self.minimizes = minimizes
        self.reference = reference
    }
}

/// 曲線の定義（`results/` の CSV のどの列を描くか）。
public struct SeriesSpec: Hashable, Sendable {
    public let file: String
    public let x: String
    public let y: [String]

    public init(file: String, x: String, y: [String]) {
        self.file = file
        self.x = x
        self.y = y
    }
}

/// ライブラリの実験（`Experiments/<キー>/`）。
public struct ResearchExperiment: Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public var title: String
    public var algorithm: String
    public var problem: String
    public var status: ExperimentStatus
    public var created: Date?
    public var finished: Date?
    public var tags: [String]
    public var parameters: [String: ParameterValue]
    public var seeds: [Int]
    public var objective: Objective?
    public var metrics: [String: Double]
    public var series: [SeriesSpec]
    public var attachments: [String]
    public var links: [String]

    public init(
        key: String, title: String, algorithm: String, problem: String, status: ExperimentStatus, created: Date?,
        finished: Date?, tags: [String], parameters: [String: ParameterValue], seeds: [Int], objective: Objective?,
        metrics: [String: Double], series: [SeriesSpec], attachments: [String], links: [String]
    ) {
        self.key = key
        self.title = title
        self.algorithm = algorithm
        self.problem = problem
        self.status = status
        self.created = created
        self.finished = finished
        self.tags = tags
        self.parameters = parameters
        self.seeds = seeds
        self.objective = objective
        self.metrics = metrics
        self.series = series
        self.attachments = attachments
        self.links = links
    }

    /// 実験のフォルダ（ライブラリのルートからのパス）。
    public var folderPath: String { "\(LibrarySection.experiments.folder)/\(key)" }
    /// 仮説と考察のノート。
    public var notePath: String { "\(folderPath)/note.md" }
}

/// 読み込んだ曲線（列名 → 値の並び）。
public struct SeriesData: Hashable, Sendable {
    public let spec: SeriesSpec
    public let x: [Double]
    /// 列名 → 値（x と同じ長さ）。
    public let columns: [String: [Double]]

    public init(spec: SeriesSpec, x: [Double], columns: [String: [Double]]) {
        self.spec = spec
        self.x = x
        self.columns = columns
    }
}

// MARK: - データと資料

/// データや資料のファイル。
public struct LibraryFile: Hashable, Sendable, Identifiable {
    public var id: String { path }
    /// ライブラリのルートからのパス。
    public let path: String
    public let name: String
    public let size: Int64
    public let modified: Date

    public init(path: String, name: String, size: Int64, modified: Date) {
        self.path = path
        self.name = name
        self.size = size
        self.modified = modified
    }
}

public enum LibraryError: Error, Equatable, Sendable {
    case storage(String)
    case notFound(String)
    case invalid(String)
    /// 書誌情報を取りに行けなかった。
    case network(String)

    public var message: String {
        switch self {
        case .storage(let message): "ライブラリに書けませんでした: \(message)"
        case .notFound(let what): "見つかりません: \(what)"
        case .invalid(let message): message
        case .network(let message): "書誌情報を取れませんでした: \(message)"
        }
    }
}
