//
//  FileSystemLibraryRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import SundeskMarkdown
import Testing

@Suite("研究ライブラリ（ファイル）")
struct FileSystemLibraryRepositoryTests {
    private let root: URL
    private let repository: FileSystemLibraryRepository

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sundesk-library-\(UUID().uuidString)")
        self.root = root
        repository = FileSystemLibraryRepository(root: { root }, markdown: SwiftMarkdownParser())
    }

    private func write(_ text: String, to relative: String) throws {
        let url = root.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test("種類ごとのフォルダと取り込み箱を作る")
    func prepares() async throws {
        try await repository.prepare()

        for folder in ["Notes", "Papers", "Experiments", "Data", "Materials", "Inbox"] {
            #expect(FileManager.default.fileExists(atPath: root.appending(path: folder).path))
        }
    }

    @Test("論文を作り、書誌情報を書き直しても論文メモの本文は残る")
    func papers() async throws {
        try await repository.prepare()
        let metadata = PaperMetadata(
            title: "A variational eigenvalue solver on a photonic quantum processor",
            authors: ["Alberto Peruzzo", "Jarrod McClean"], year: 2014, venue: "Nature Communications",
            arxiv: "1304.3061", doi: "10.1038/ncomms5213")

        var paper = try await repository.createPaper(metadata, pdf: nil, status: .unread, tags: ["VQE"])
        #expect(paper.key == "peruzzo2014-variational")
        try write(
            (try String(contentsOf: root.appending(path: paper.notePath), encoding: .utf8)) + "自分のメモ\n",
            to: paper.notePath)

        paper.status = .read
        paper.tags = ["VQE", "量子化学"]
        try await repository.savePaper(paper)

        let loaded = try #require(try await repository.papers().first)
        #expect(loaded.metadata == metadata)
        #expect(loaded.status == .read)
        #expect(loaded.tags == ["VQE", "量子化学"])
        #expect(try String(contentsOf: root.appending(path: paper.notePath), encoding: .utf8).contains("自分のメモ"))
    }

    @Test("実験を作り、結果の CSV を取り込むと曲線として読める")
    func experiments() async throws {
        try await repository.prepare()
        let experiment = try await repository.createExperiment(title: "GA on Max-Cut", algorithm: "GA", problem: "G1")
        let csv = FileManager.default.temporaryDirectory.appending(path: "trace-\(UUID().uuidString).csv")
        try Data("generation,best,mean\n0,5,3\n1,7,4.5\n2,8,6\n".utf8).write(to: csv)

        try await repository.attach([csv], to: experiment.key)

        let loaded = try #require(try await repository.experiments().first)
        #expect(loaded.title == "GA on Max-Cut")
        #expect(loaded.series.first?.x == "generation")
        #expect(loaded.series.first?.y == ["best", "mean"])
        let series = try await repository.series(of: loaded)
        #expect(series.first?.x == [0, 1, 2])
        #expect(series.first?.columns["best"] == [5, 7, 8])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: loaded.notePath).path))
    }

    @Test("取り込み箱の終わった実行だけを、実験に移す")
    func importsInbox() async throws {
        try await repository.prepare()
        let run = """
            {"title": "VQE H2", "algorithm": "VQE", "problem": "H2", "status": "done",
             "created": "2026-09-20T10:00:00+09:00", "parameters": {"ansatz": "RY", "layers": 2, "shots": false},
             "seed": 7, "objective": {"name": "energy", "direction": "minimize", "reference": -1.137},
             "metrics": {"best_energy": -1.13},
             "series": [{"file": "results/trace.csv", "x": "iteration", "y": ["energy"]}],
             "note": "## 考察\\n収束した"}
            """
        try write(run, to: "Inbox/run-1/run.json")
        try write("iteration,energy\n0,-0.5\n1,-1.13\n", to: "Inbox/run-1/results/trace.csv")
        try write("", to: "Inbox/run-1/.complete")
        try write(run, to: "Inbox/run-2/run.json")

        let imported = try await repository.importInbox()

        #expect(imported == ["2026-09-20-vqe-h2"])
        let experiment = try #require(try await repository.experiments().first)
        #expect(experiment.parameters == ["ansatz": .text("RY"), "layers": .number(2), "shots": .flag(false)])
        #expect(experiment.seeds == [7])
        #expect(experiment.objective == Objective(name: "energy", minimizes: true, reference: -1.137))
        #expect(try await repository.series(of: experiment).first?.columns["energy"] == [-0.5, -1.13])
        let note = try String(contentsOf: root.appending(path: experiment.notePath), encoding: .utf8)
        #expect(note.contains("収束した"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Inbox/run-2").path))
    }

    @Test("ファイルを種類のフォルダに取り込み、名前が重なれば番号を付ける")
    func importsFiles() async throws {
        try await repository.prepare()
        let file = FileManager.default.temporaryDirectory.appending(path: "qubo.json")
        try Data("{}".utf8).write(to: file)

        let first = try await repository.importFiles([file], into: .data)
        let second = try await repository.importFiles([file], into: .data)

        #expect(first == ["Data/qubo.json"])
        #expect(second == ["Data/qubo-2.json"])
        #expect(try await repository.files(in: .data).map(\.name) == ["qubo-2.json", "qubo.json"])
    }

    @Test("書き出して、戻せる（今のライブラリは横に残す）")
    func exportAndRestore() async throws {
        try await repository.prepare()
        _ = try await repository.createNote(named: "研究ログ")
        let exported = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")

        try await repository.export(to: exported)
        try FileManager.default.removeItem(at: root.appending(path: "Notes/研究ログ.md"))
        try await repository.restore(from: exported)

        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Notes/研究ログ.md").path))
        await #expect(throws: LibraryError.invalid("選んだフォルダは sundesk のライブラリではありません")) {
            try await repository.restore(from: FileManager.default.temporaryDirectory.appending(path: "ない"))
        }
    }
}

@Suite("書誌情報の読み取り")
struct BibliographyParsingTests {
    @Test("論文の ID を、URL や DOI から読み取る")
    func identifiers() {
        #expect(PaperIdentifier(parsing: "https://arxiv.org/abs/1304.3061v2") == .arxiv("1304.3061"))
        #expect(PaperIdentifier(parsing: "arXiv:1411.4028") == .arxiv("1411.4028"))
        #expect(
            PaperIdentifier(parsing: "https://doi.org/10.1103/PhysRevE.58.5355.") == .doi("10.1103/PhysRevE.58.5355"))
        #expect(PaperIdentifier(parsing: "10.48550/arXiv.1604.00772") == .arxiv("1604.00772"))
        #expect(PaperIdentifier(parsing: "量子アニーリング") == nil)
    }
}

/// 本物の arXiv と Crossref に問い合わせる。`SUNDESK_NETWORK=1` のときだけ走る。
@Suite("書誌情報（通信）", .enabled(if: ProcessInfo.processInfo.environment["SUNDESK_NETWORK"] == "1"))
struct OnlineBibliographyTests {
    @Test("arXiv の ID から書誌情報を取る")
    func arxiv() async throws {
        let metadata = try await OnlineBibliography().metadata(for: .arxiv("1304.3061"))

        print(metadata)
        #expect(metadata.title.contains("variational eigenvalue solver"))
        #expect(metadata.authors.first == "Alberto Peruzzo")
        #expect(metadata.year == 2013)
    }

    @Test("DOI から書誌情報を取る")
    func doi() async throws {
        let metadata = try await OnlineBibliography().metadata(for: .doi("10.1103/PhysRevE.58.5355"))

        print(metadata)
        #expect(metadata.title.lowercased().contains("quantum annealing"))
        #expect(metadata.year == 1998)
        #expect(metadata.venue == "Physical Review E")
    }
}

@Suite("研究ライブラリの見本を読む（結合テスト）")
struct SampleLibraryTests {
    private static let sampleLibrary = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SampleLibrary", directoryHint: .isDirectory)

    @Test("論文、実験、曲線をすべて読め、取り込み箱の実行を実験に移せる")
    func readsAndImportsSample() async throws {
        // 見本を汚さないよう、写しで試す
        let root = FileManager.default.temporaryDirectory.appending(path: "sundesk-sample-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: Self.sampleLibrary, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSystemLibraryRepository(
            root: { root }, markdown: SwiftMarkdownParser(), inbox: { root.appending(path: "Inbox") })

        let papers = try await repository.papers()
        #expect(papers.count == 8)
        #expect(papers.allSatisfy { !$0.metadata.title.isEmpty && $0.metadata.year != nil })

        let experiments = try await repository.experiments()
        #expect(experiments.count == 10)
        for experiment in experiments where experiment.status == .done {
            let series = try await repository.series(of: experiment)
            #expect(!series.isEmpty, "\(experiment.key) の曲線がない")
            #expect(series.allSatisfy { !$0.columns.isEmpty }, "\(experiment.key) の曲線が空")
        }

        let imported = try await repository.importInbox()
        #expect(imported.count == 1)
        let key = try #require(imported.first)
        let experiment = try #require(try await repository.experiments().first { $0.key == key })
        #expect(experiment.algorithm == "SA")
        let note = try String(contentsOf: root.appending(path: experiment.notePath), encoding: .utf8)
        #expect(note.contains("仮説"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Inbox").path).isEmpty)
    }
}
