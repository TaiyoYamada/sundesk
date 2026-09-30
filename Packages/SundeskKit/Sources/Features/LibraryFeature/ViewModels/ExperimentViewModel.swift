//
//  ExperimentViewModel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 1 回の実験。設定、指標、収束の曲線、図を見て、結果を取り込む。
@MainActor
@Observable
public final class ExperimentViewModel {
    public let key: String
    public var title = ""
    public var algorithm = ""
    public var problem = ""
    /// 状態（`planned`、`running`、`done`、`failed`）。
    public var status = ExperimentStatus.planned.rawValue
    public private(set) var date = ""
    public private(set) var parameters: [KeyValueRow] = []
    public private(set) var metrics: [KeyValueRow] = []
    public private(set) var objective: String?
    public private(set) var charts: [ChartItem] = []
    public private(set) var figures: [URL] = []
    public private(set) var otherFiles: [String] = []
    public private(set) var links: [String] = []
    public private(set) var notePath = ""
    public private(set) var folderURL: URL?
    public var errorMessage: String?

    @ObservationIgnored private let library: any ManageLibraryUseCase
    @ObservationIgnored private var experiment: ResearchExperiment?

    public static let algorithms = ["VQE", "QAOA", "GA", "PSO", "SA", "QA", "CMA-ES", "DE", "ACO", "その他"]
    /// 選べる状態（値と名前）。
    public static let statuses = ExperimentStatus.allCases.map { KeyValueRow(key: $0.rawValue, value: $0.title) }

    public init(key: String, library: any ManageLibraryUseCase) {
        self.key = key
        self.library = library
    }

    public func load() async {
        guard let experiment = try? await library.experiments().first(where: { $0.key == key }) else {
            errorMessage = "実験が見つかりません（\(key)）"
            return
        }
        self.experiment = experiment
        title = experiment.title
        algorithm = experiment.algorithm
        problem = experiment.problem
        status = experiment.status.rawValue
        date = [experiment.created, experiment.finished].compactMap {
            $0?.formatted(date: .abbreviated, time: .shortened)
        }
        .joined(separator: " 〜 ")
        parameters = experiment.parameters.sorted { $0.key < $1.key }.map {
            KeyValueRow(key: $0.key, value: $0.value.description)
        }
        if !experiment.seeds.isEmpty {
            parameters.append(KeyValueRow(key: "種", value: experiment.seeds.map(String.init).joined(separator: ", ")))
        }
        metrics = experiment.metrics.sorted { $0.key < $1.key }.map {
            KeyValueRow(key: $0.key, value: ExperimentFormat.number($0.value))
        }
        objective = experiment.objective.map { objective in
            "\(objective.name) を\(objective.minimizes ? "最小化" : "最大化")"
                + (objective.reference.map { "（最適値 \(ExperimentFormat.number($0))）" } ?? "")
        }
        let root = library.root()
        let folder = root.appending(path: experiment.folderPath)
        folderURL = folder
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "svg"]
        figures = experiment.attachments.filter {
            imageExtensions.contains(($0 as NSString).pathExtension.lowercased())
        }
        .map { folder.appending(path: $0) }
        otherFiles = experiment.attachments.filter {
            !imageExtensions.contains(($0 as NSString).pathExtension.lowercased())
        }
        links = experiment.links
        notePath = experiment.notePath
        let series = (try? await library.series(of: experiment)) ?? []
        charts = series.map { ChartItem($0, reference: experiment.objective?.reference) }
    }

    /// 名前、アルゴリズム、問題、状態を保存する。
    public func save() async {
        guard var experiment else { return }
        experiment.title = title
        experiment.algorithm = algorithm
        experiment.problem = problem
        experiment.status = ExperimentStatus(rawValue: status) ?? .planned
        if experiment.status == .done && experiment.finished == nil { experiment.finished = .now }
        do {
            try await library.saveExperiment(experiment)
            self.experiment = experiment
        } catch {
            errorMessage = error.message
        }
    }

    /// 結果のファイルや図を取り込む（CSV は曲線になる）。
    public func attach(_ urls: [URL]) async {
        guard let experiment else { return }
        for url in urls { _ = url.startAccessingSecurityScopedResource() }
        defer { for url in urls { url.stopAccessingSecurityScopedResource() } }
        do {
            try await library.attach(urls, to: experiment)
            await load()
        } catch {
            errorMessage = error.message
        }
    }
}

/// 複数の実験を並べて比べる。
@MainActor
@Observable
public final class ComparisonViewModel {
    public let keys: [String]
    public private(set) var curves: [CurveItem] = []
    public private(set) var metricNames: [String] = []
    public private(set) var rows: [ComparisonRow] = []
    /// 値の違うパラメータだけ。
    public private(set) var differingParameters: [String] = []
    public private(set) var reference: Double?
    /// 横軸を対数にするか（収束の違いが見やすい）。
    public var logScaleY = false

    @ObservationIgnored private let library: any ManageLibraryUseCase

    public init(keys: [String], library: any ManageLibraryUseCase) {
        self.keys = keys
        self.library = library
    }

    public func load() async {
        let all = (try? await library.experiments()) ?? []
        let experiments = keys.compactMap { key in all.first { $0.key == key } }
        var pairs: [(ResearchExperiment, [SeriesData])] = []
        for experiment in experiments {
            pairs.append((experiment, (try? await library.series(of: experiment)) ?? []))
        }
        curves = ExperimentComparison.curves(pairs).map(CurveItem.init)
        metricNames = ExperimentComparison.metricNames(experiments)
        let parameterNames = Set(experiments.flatMap(\.parameters.keys)).sorted()
        differingParameters = parameterNames.filter { name in
            Set(experiments.map { $0.parameters[name]?.description ?? "—" }).count > 1
        }
        reference = experiments.compactMap(\.objective?.reference).first
        rows = experiments.map { experiment in
            ComparisonRow(
                key: experiment.key, title: experiment.title, algorithm: experiment.algorithm,
                metrics: metricNames.map { experiment.metrics[$0].map(ExperimentFormat.number) ?? "—" },
                parameters: differingParameters.map { experiment.parameters[$0]?.description ?? "—" },
                minimizes: experiment.objective?.minimizes ?? true)
        }
    }

    /// 指標ごとに最もよい値の行（小さいほどよいかは、目的関数の向きで決める）。
    public func isBest(row: ComparisonRow, metricIndex: Int) -> Bool {
        let values = rows.compactMap { Double($0.metrics[metricIndex]) }
        guard values.count > 1, let value = Double(row.metrics[metricIndex]) else { return false }
        return row.minimizes ? value == values.min() : value == values.max()
    }
}

// MARK: - 表示用の型

public struct KeyValueRow: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: String
}

/// 1 つの CSV から描く、いくつかの曲線。
public struct ChartItem: Identifiable, Hashable, Sendable {
    public var id: String { file }
    public let file: String
    public let xLabel: String
    public let points: [ChartPoint]
    public let reference: Double?

    init(_ data: SeriesData, reference: Double?) {
        file = data.spec.file
        xLabel = data.spec.x
        points = data.spec.y.flatMap { name in
            zip(data.x, data.columns[name] ?? []).filter { $0.0.isFinite && $0.1.isFinite }.map {
                ChartPoint(series: name, x: $0.0, y: $0.1)
            }
        }
        self.reference = reference
    }
}

public struct ChartPoint: Hashable, Sendable {
    public let series: String
    public let x: Double
    public let y: Double
}

public struct CurveItem: Identifiable, Hashable, Sendable {
    public var id: String { experimentKey }
    public let experimentKey: String
    public let label: String
    public let points: [ChartPoint]

    init(_ curve: ComparedCurve) {
        experimentKey = curve.experimentKey
        label = curve.label
        points = zip(curve.x, curve.y).filter { $0.0.isFinite && $0.1.isFinite }.map {
            ChartPoint(series: curve.label, x: $0.0, y: $0.1)
        }
    }
}

public struct ComparisonRow: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let algorithm: String
    public let metrics: [String]
    public let parameters: [String]
    public let minimizes: Bool
}
