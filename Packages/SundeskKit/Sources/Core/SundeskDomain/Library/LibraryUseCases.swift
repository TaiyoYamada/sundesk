//
//  LibraryUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// 研究ライブラリのファイルを読み書きする（形式は docs/library-format.md）。
public protocol LibraryRepository: Sendable {
    /// ライブラリのフォルダ（なければ種類ごとのフォルダも作る）。
    func root() -> URL
    func prepare() async throws(LibraryError)

    func papers() async throws(LibraryError) -> [Paper]
    /// 論文を新しく作る。`pdf` があれば `paper.pdf` として写す。
    func createPaper(
        _ metadata: PaperMetadata, pdf: URL?, status: ReadingStatus, tags: [String]
    ) async throws(LibraryError) -> Paper
    /// 書誌情報、読んだ状態、タグを書き直す（論文メモの本文は残す）。
    func savePaper(_ paper: Paper) async throws(LibraryError)
    func attachPDF(_ pdf: URL, to key: String) async throws(LibraryError)

    func experiments() async throws(LibraryError) -> [ResearchExperiment]
    func createExperiment(title: String, algorithm: String, problem: String) async throws(LibraryError)
        -> ResearchExperiment
    func saveExperiment(_ experiment: ResearchExperiment) async throws(LibraryError)
    func series(of experiment: ResearchExperiment) async throws(LibraryError) -> [SeriesData]
    /// 結果や図のファイルを実験に取り込む（CSV は曲線として登録する）。
    func attach(_ files: [URL], to key: String) async throws(LibraryError)

    func files(in section: LibrarySection) async throws(LibraryError) -> [LibraryFile]
    /// ファイルを種類のフォルダに写す。写した先のパスを返す。
    func importFiles(_ urls: [URL], into section: LibrarySection) async throws(LibraryError) -> [String]
    func createNote(named name: String) async throws(LibraryError) -> String
    /// 取り込み箱の終わった実行を、実験に移す。移した実験のキーを返す。
    func importInbox() async throws(LibraryError) -> [String]
    func delete(_ path: String) async throws(LibraryError)

    /// ライブラリを丸ごと書き出す。
    func export(to destination: URL) async throws(LibraryError)
    /// 書き出したものから戻す（今のライブラリは置き換える）。
    func restore(from source: URL) async throws(LibraryError)
}

/// 論文の書誌情報を、arXiv や Crossref から取る（通信するのはここだけ）。
public protocol BibliographyService: Sendable {
    func metadata(for identifier: PaperIdentifier) async throws(LibraryError) -> PaperMetadata
    /// arXiv の PDF を取ってくる。
    func downloadPDF(arxiv: String) async throws(LibraryError) -> URL
}

/// PDF から論文の手がかりを読む。
public protocol PDFInspecting: Sendable {
    /// 最初の数ページに書かれた arXiv の ID か DOI。
    func identifier(in pdf: URL) -> PaperIdentifier?
    /// PDF の属性や 1 ページ目から推測した題名。
    func title(in pdf: URL) -> String?
}

// MARK: - UseCase

/// ライブラリの操作（画面が使うもの一式）。
public protocol ManageLibraryUseCase: Sendable {
    func prepare() async throws(LibraryError)
    func papers() async throws(LibraryError) -> [Paper]
    /// arXiv の ID か DOI から論文を足す。`downloadsPDF` なら arXiv の PDF も取ってくる。
    func addPaper(identifier: PaperIdentifier, downloadsPDF: Bool) async throws(LibraryError) -> Paper
    /// PDF を取り込んで論文を足す。PDF に arXiv の ID や DOI があれば、書誌情報を取りに行く。
    func importPaper(pdf: URL) async throws(LibraryError) -> Paper
    func savePaper(_ paper: Paper) async throws(LibraryError)
    /// 書誌情報を取り直す（arXiv の ID か DOI があるとき）。
    func refreshMetadata(of paper: Paper) async throws(LibraryError) -> Paper
    func attachPDF(_ pdf: URL, to paper: Paper) async throws(LibraryError)

    func experiments() async throws(LibraryError) -> [ResearchExperiment]
    func createExperiment(title: String, algorithm: String, problem: String) async throws(LibraryError)
        -> ResearchExperiment
    func saveExperiment(_ experiment: ResearchExperiment) async throws(LibraryError)
    func series(of experiment: ResearchExperiment) async throws(LibraryError) -> [SeriesData]
    func attach(_ files: [URL], to experiment: ResearchExperiment) async throws(LibraryError)

    func files(in section: LibrarySection) async throws(LibraryError) -> [LibraryFile]
    func importFiles(_ urls: [URL], into section: LibrarySection) async throws(LibraryError) -> [String]
    func createNote(named name: String) async throws(LibraryError) -> String
    func importInbox() async throws(LibraryError) -> [String]
    func delete(_ path: String) async throws(LibraryError)
    func export(to destination: URL) async throws(LibraryError)
    func restore(from source: URL) async throws(LibraryError)
    func root() -> URL
}

public struct LibraryInteractor: ManageLibraryUseCase {
    private let repository: any LibraryRepository
    private let bibliography: any BibliographyService
    private let pdfs: any PDFInspecting

    public init(repository: any LibraryRepository, bibliography: any BibliographyService, pdfs: any PDFInspecting) {
        self.repository = repository
        self.bibliography = bibliography
        self.pdfs = pdfs
    }

    public func prepare() async throws(LibraryError) {
        try await repository.prepare()
    }

    public func papers() async throws(LibraryError) -> [Paper] {
        try await repository.papers()
    }

    public func addPaper(identifier: PaperIdentifier, downloadsPDF: Bool) async throws(LibraryError) -> Paper {
        if let existing = try await repository.papers().first(where: { $0.matches(identifier) }) {
            return existing
        }
        let metadata = try await bibliography.metadata(for: identifier)
        var pdf: URL?
        if downloadsPDF, let arxiv = metadata.arxiv {
            pdf = try? await bibliography.downloadPDF(arxiv: arxiv)
        }
        defer { if let pdf { try? FileManager.default.removeItem(at: pdf) } }
        return try await repository.createPaper(metadata, pdf: pdf, status: .unread, tags: [])
    }

    public func importPaper(pdf: URL) async throws(LibraryError) -> Paper {
        var metadata: PaperMetadata?
        if let identifier = pdfs.identifier(in: pdf) {
            if let existing = try await repository.papers().first(where: { $0.matches(identifier) }) {
                if existing.pdfPath == nil { try await repository.attachPDF(pdf, to: existing.key) }
                return try await repository.papers().first { $0.key == existing.key } ?? existing
            }
            metadata = try? await bibliography.metadata(for: identifier)
            if metadata == nil {
                // 通信できなくても、ID だけは残しておく
                switch identifier {
                case .arxiv(let id): metadata = PaperMetadata(title: pdfs.title(in: pdf) ?? id, arxiv: id)
                case .doi(let doi): metadata = PaperMetadata(title: pdfs.title(in: pdf) ?? doi, doi: doi)
                }
            }
        }
        let fallback = PaperMetadata(title: pdfs.title(in: pdf) ?? pdf.deletingPathExtension().lastPathComponent)
        return try await repository.createPaper(metadata ?? fallback, pdf: pdf, status: .unread, tags: [])
    }

    public func savePaper(_ paper: Paper) async throws(LibraryError) {
        try await repository.savePaper(paper)
    }

    public func refreshMetadata(of paper: Paper) async throws(LibraryError) -> Paper {
        let identifier: PaperIdentifier
        if let arxiv = paper.metadata.arxiv {
            identifier = .arxiv(arxiv)
        } else if let doi = paper.metadata.doi {
            identifier = .doi(doi)
        } else {
            throw .invalid("arXiv の ID か DOI がないので、書誌情報を取れません")
        }
        var updated = paper
        updated.metadata = try await bibliography.metadata(for: identifier)
        try await repository.savePaper(updated)
        return updated
    }

    public func attachPDF(_ pdf: URL, to paper: Paper) async throws(LibraryError) {
        try await repository.attachPDF(pdf, to: paper.key)
    }

    public func experiments() async throws(LibraryError) -> [ResearchExperiment] {
        try await repository.experiments()
    }

    public func createExperiment(title: String, algorithm: String, problem: String) async throws(LibraryError)
        -> ResearchExperiment
    {
        try await repository.createExperiment(title: title, algorithm: algorithm, problem: problem)
    }

    public func saveExperiment(_ experiment: ResearchExperiment) async throws(LibraryError) {
        try await repository.saveExperiment(experiment)
    }

    public func series(of experiment: ResearchExperiment) async throws(LibraryError) -> [SeriesData] {
        try await repository.series(of: experiment)
    }

    public func attach(_ files: [URL], to experiment: ResearchExperiment) async throws(LibraryError) {
        try await repository.attach(files, to: experiment.key)
    }

    public func files(in section: LibrarySection) async throws(LibraryError) -> [LibraryFile] {
        try await repository.files(in: section)
    }

    public func importFiles(_ urls: [URL], into section: LibrarySection) async throws(LibraryError) -> [String] {
        try await repository.importFiles(urls, into: section)
    }

    public func createNote(named name: String) async throws(LibraryError) -> String {
        try await repository.createNote(named: name)
    }

    public func importInbox() async throws(LibraryError) -> [String] {
        try await repository.importInbox()
    }

    public func delete(_ path: String) async throws(LibraryError) {
        try await repository.delete(path)
    }

    public func export(to destination: URL) async throws(LibraryError) {
        try await repository.export(to: destination)
    }

    public func restore(from source: URL) async throws(LibraryError) {
        try await repository.restore(from: source)
    }

    public func root() -> URL {
        repository.root()
    }
}

extension Paper {
    /// 同じ論文か（arXiv の ID か DOI が一致する）。
    func matches(_ identifier: PaperIdentifier) -> Bool {
        switch identifier {
        case .arxiv(let id): metadata.arxiv == id
        case .doi(let doi): metadata.doi?.lowercased() == doi.lowercased()
        }
    }
}

// MARK: - 比べる

/// 実験を並べて比べるときの、1 本の曲線。
public struct ComparedCurve: Hashable, Sendable {
    public let experimentKey: String
    public let label: String
    public let x: [Double]
    public let y: [Double]

    public init(experimentKey: String, label: String, x: [Double], y: [Double]) {
        self.experimentKey = experimentKey
        self.label = label
        self.x = x
        self.y = y
    }
}

public enum ExperimentComparison {
    /// 比べる曲線。各実験の最初の曲線から、目的関数の名前（なければ最初の y）の列を選ぶ。
    public static func curves(_ experiments: [(ResearchExperiment, [SeriesData])]) -> [ComparedCurve] {
        experiments.compactMap { experiment, series in
            guard let data = series.first else { return nil }
            let preferred = ["best", experiment.objective?.name].compactMap { $0 }
            let column =
                preferred.first { data.columns[$0] != nil } ?? data.spec.y.first { data.columns[$0] != nil }
            guard let column, let values = data.columns[column] else { return nil }
            return ComparedCurve(
                experimentKey: experiment.key, label: "\(experiment.title)（\(column)）", x: data.x, y: values)
        }
    }

    /// 並べる指標の名前（どれかの実験にあるもの、名前の順）。
    public static func metricNames(_ experiments: [ResearchExperiment]) -> [String] {
        Set(experiments.flatMap(\.metrics.keys)).sorted()
    }
}
