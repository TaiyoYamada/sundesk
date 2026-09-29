//
//  LibraryViewModelTests.swift
//  LibraryFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import LibraryFeature
import SundeskDomain
import Testing

@MainActor
@Suite("ライブラリの画面")
struct LibraryViewModelTests {
    private func experiment(
        _ key: String, algorithm: String, best: Double, population: Double, minimizes: Bool = true
    ) -> ResearchExperiment {
        ResearchExperiment(
            key: key, title: "\(algorithm) の実験", algorithm: algorithm, problem: "Max-Cut G1", status: .done,
            created: Date(timeIntervalSince1970: 0), finished: nil, tags: [],
            parameters: ["population": .number(population), "crossover": .text("uniform")], seeds: [1],
            objective: Objective(name: "cut", minimizes: minimizes, reference: 12), metrics: ["best_cut": best],
            series: [SeriesSpec(file: "results/trace.csv", x: "generation", y: ["best"])], attachments: [], links: [])
    }

    @Test("一覧を読み、取り込み箱から取り込んだら知らせる。論文は絞り込みと並べ替えができる")
    func loadsAndFilters() async {
        let library = LibraryStub(papers: [
            Paper(
                key: "a", metadata: PaperMetadata(title: "QAOA", authors: ["Edward Farhi"], year: 2014), status: .read,
                tags: [], added: nil, pdfPath: nil),
            Paper(
                key: "b", metadata: PaperMetadata(title: "VQE", authors: ["Alberto Peruzzo"], year: 2013),
                status: .unread,
                tags: ["VQE"], added: nil, pdfPath: "Papers/b/paper.pdf"),
        ])
        let viewModel = LibraryViewModel(library: library, observeChanges: ChangesStub())

        await viewModel.refresh()

        #expect(viewModel.message == "取り込み箱から 1 件の実験を取り込みました")
        #expect(viewModel.papers.map(\.authors) == ["Farhi", "Peruzzo"])
        viewModel.statusFilter = "未読"
        #expect(viewModel.shownPapers.map(\.key) == ["b"])
        viewModel.statusFilter = nil
        viewModel.paperSort = .year
        #expect(viewModel.shownPapers.map(\.key) == ["a", "b"])
        viewModel.filterText = "vqe"
        #expect(viewModel.shownPapers.map(\.key) == ["b"])
    }

    @Test("論文の ID が読めなければ断る")
    func rejectsBadIdentifier() async {
        let viewModel = LibraryViewModel(library: LibraryStub(), observeChanges: ChangesStub())

        let key = await viewModel.addPaper(identifier: "量子アニーリング", downloadsPDF: false)

        #expect(key == nil)
        #expect(viewModel.errorMessage?.contains("arXiv の ID") == true)
    }

    @Test("比べると、最もよい値と、値の違うパラメータが分かる")
    func compares() async {
        let library = LibraryStub(experiments: [
            experiment("ga", algorithm: "GA", best: 11, population: 50, minimizes: false),
            experiment("pso", algorithm: "PSO", best: 12, population: 30, minimizes: false),
        ])
        let viewModel = ComparisonViewModel(keys: ["ga", "pso"], library: library)

        await viewModel.load()

        #expect(viewModel.metricNames == ["best_cut"])
        #expect(viewModel.differingParameters == ["population"])
        #expect(viewModel.curves.map(\.label) == ["GA の実験（best）", "PSO の実験（best）"])
        #expect(viewModel.isBest(row: viewModel.rows[1], metricIndex: 0))
        #expect(!viewModel.isBest(row: viewModel.rows[0], metricIndex: 0))
        #expect(viewModel.reference == 12)
    }

    @Test("実験の設定、指標、目的関数を見やすくする")
    func experimentDetails() async {
        let library = LibraryStub(experiments: [experiment("ga", algorithm: "GA", best: 11.5, population: 50)])
        let viewModel = ExperimentViewModel(key: "ga", library: library)

        await viewModel.load()

        #expect(viewModel.parameters.map(\.value) == ["uniform", "50", "1"])
        #expect(viewModel.metrics.first?.value == "11.5")
        #expect(viewModel.objective == "cut を最小化（最適値 12）")
        #expect(viewModel.charts.first?.points.count == 3)
    }
}

private struct ChangesStub: ObserveVaultChangesUseCase {
    func callAsFunction() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private final class LibraryStub: ManageLibraryUseCase, @unchecked Sendable {
    let storedPapers: [Paper]
    let storedExperiments: [ResearchExperiment]
    private var inbox = ["2026-09-20-vqe"]

    init(papers: [Paper] = [], experiments: [ResearchExperiment] = []) {
        storedPapers = papers
        storedExperiments = experiments
    }

    func prepare() async throws(LibraryError) {}
    func papers() async throws(LibraryError) -> [Paper] { storedPapers }
    func addPaper(identifier: PaperIdentifier, downloadsPDF: Bool) async throws(LibraryError) -> Paper {
        storedPapers[0]
    }
    func importPaper(pdf: URL) async throws(LibraryError) -> Paper { storedPapers[0] }
    func savePaper(_ paper: Paper) async throws(LibraryError) {}
    func refreshMetadata(of paper: Paper) async throws(LibraryError) -> Paper { paper }
    func attachPDF(_ pdf: URL, to paper: Paper) async throws(LibraryError) {}
    func experiments() async throws(LibraryError) -> [ResearchExperiment] { storedExperiments }
    func createExperiment(title: String, algorithm: String, problem: String) async throws(LibraryError)
        -> ResearchExperiment
    {
        storedExperiments[0]
    }
    func saveExperiment(_ experiment: ResearchExperiment) async throws(LibraryError) {}
    func series(of experiment: ResearchExperiment) async throws(LibraryError) -> [SeriesData] {
        [
            SeriesData(
                spec: experiment.series[0], x: [0, 1, 2],
                columns: ["best": experiment.algorithm == "GA" ? [8, 10, 11] : [9, 11, 12]])
        ]
    }
    func attach(_ files: [URL], to experiment: ResearchExperiment) async throws(LibraryError) {}
    func files(in section: LibrarySection) async throws(LibraryError) -> [LibraryFile] { [] }
    func importFiles(_ urls: [URL], into section: LibrarySection) async throws(LibraryError) -> [String] { [] }
    func createNote(named name: String) async throws(LibraryError) -> String { "Notes/\(name).md" }
    func importInbox() async throws(LibraryError) -> [String] {
        defer { inbox = [] }
        return inbox
    }
    func delete(_ path: String) async throws(LibraryError) {}
    func export(to destination: URL) async throws(LibraryError) {}
    func restore(from source: URL) async throws(LibraryError) {}
    func root() -> URL { URL(filePath: "/library") }
}
