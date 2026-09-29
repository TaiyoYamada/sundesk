//
//  FileSystemLibraryRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

/// 研究ライブラリを、ふつうのファイルとして読み書きする（docs/library-format.md）。
public struct FileSystemLibraryRepository: LibraryRepository {
    private let rootURL: @Sendable () -> URL
    private let markdown: any MarkdownParsing
    private let inboxURL: @Sendable () -> URL

    /// - Parameters:
    ///   - root: ライブラリのフォルダ。
    ///   - inbox: 取り込み箱。既定はライブラリの `Inbox/`（環境変数 `SUNDESK_INBOX` があればそちら）。
    public init(
        root: @escaping @Sendable () -> URL, markdown: any MarkdownParsing,
        inbox: (@Sendable () -> URL)? = nil
    ) {
        self.rootURL = root
        self.markdown = markdown
        self.inboxURL =
            inbox ?? {
                if let path = ProcessInfo.processInfo.environment["SUNDESK_INBOX"], !path.isEmpty {
                    return URL(filePath: path, directoryHint: .isDirectory)
                }
                return root().appending(path: LibrarySection.inboxFolder, directoryHint: .isDirectory)
            }
    }

    public func root() -> URL {
        rootURL()
    }

    private var fileManager: FileManager { .default }

    private func url(_ relative: String) -> URL {
        rootURL().appending(path: relative)
    }

    private func folder(_ section: LibrarySection) -> URL {
        rootURL().appending(path: section.folder, directoryHint: .isDirectory)
    }

    public func prepare() async throws(LibraryError) {
        try storage {
            for section in LibrarySection.allCases {
                try fileManager.createDirectory(at: folder(section), withIntermediateDirectories: true)
            }
            try fileManager.createDirectory(at: inboxURL(), withIntermediateDirectories: true)
        }
    }

    // MARK: - 論文

    public func papers() async throws(LibraryError) -> [Paper] {
        subfolders(of: folder(.papers)).compactMap { directory in
            let key = directory.lastPathComponent
            let note = directory.appending(path: "note.md")
            guard let source = try? String(contentsOf: note, encoding: .utf8) else { return nil }
            let properties = markdown.analyze(source, path: "\(LibrarySection.papers.folder)/\(key)/note.md").properties
            return LibraryText.paper(
                key: key, properties: properties, hasPDF: exists(directory.appending(path: "paper.pdf")))
        }
        .sorted { ($0.added ?? .distantPast, $0.metadata.title) > ($1.added ?? .distantPast, $1.metadata.title) }
    }

    public func createPaper(
        _ metadata: PaperMetadata, pdf: URL?, status: ReadingStatus, tags: [String]
    ) async throws(LibraryError) -> Paper {
        let key = uniqueKey(LibraryText.paperKey(for: metadata), in: folder(.papers))
        let directory = folder(.papers).appending(path: key, directoryHint: .isDirectory)
        let paper = Paper(
            key: key, metadata: metadata, status: status, tags: tags, added: .now, pdfPath: pdf == nil ? nil : "")
        try storage {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let body =
                "# \(metadata.title)\n\n" + (metadata.abstract.map { "## 概要\n\n\($0)\n\n" } ?? "")
                + "## 要点\n\n## メモ\n"
            try write(LibraryText.frontmatter(for: paper) + body, to: directory.appending(path: "note.md"))
            if let pdf { try copy(pdf, to: directory.appending(path: "paper.pdf")) }
        }
        return try await papers().first { $0.key == key } ?? paper
    }

    public func savePaper(_ paper: Paper) async throws(LibraryError) {
        let note = url(paper.notePath)
        try storage {
            let source = (try? String(contentsOf: note, encoding: .utf8)) ?? ""
            try write(LibraryText.frontmatter(for: paper) + LibraryText.body(of: source), to: note)
        }
    }

    public func attachPDF(_ pdf: URL, to key: String) async throws(LibraryError) {
        let destination = folder(.papers).appending(path: key).appending(path: "paper.pdf")
        try storage { try copy(pdf, to: destination) }
    }

    // MARK: - 実験

    public func experiments() async throws(LibraryError) -> [ResearchExperiment] {
        subfolders(of: folder(.experiments)).compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appending(path: "experiment.json")),
                let file = try? JSONDecoder().decode(ExperimentFile.self, from: data)
            else { return nil }
            return file.experiment(key: directory.lastPathComponent)
        }
        .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    public func createExperiment(
        title: String, algorithm: String, problem: String
    ) async throws(LibraryError) -> ResearchExperiment {
        let key = uniqueKey(LibraryText.experimentKey(title: title, date: .now), in: folder(.experiments))
        let experiment = ResearchExperiment(
            key: key, title: title, algorithm: algorithm, problem: problem, status: .planned, created: .now,
            finished: nil, tags: [], parameters: [:], seeds: [], objective: nil, metrics: [:], series: [],
            attachments: [], links: [])
        try await saveExperiment(experiment)
        try storage {
            let note = url(experiment.notePath)
            if !exists(note) {
                try write(LibraryText.experimentNote(title: title, body: nil), to: note)
            }
        }
        return experiment
    }

    public func saveExperiment(_ experiment: ResearchExperiment) async throws(LibraryError) {
        let directory = url(experiment.folderPath)
        try storage {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(ExperimentFile(experiment)).write(
                to: directory.appending(path: "experiment.json"), options: .atomic)
        }
    }

    public func series(of experiment: ResearchExperiment) async throws(LibraryError) -> [SeriesData] {
        experiment.series.compactMap { spec in
            guard
                let text = try? String(
                    contentsOf: url(experiment.folderPath).appending(path: spec.file), encoding: .utf8)
            else { return nil }
            return CSVTable(text).series(spec)
        }
    }

    public func attach(_ files: [URL], to key: String) async throws(LibraryError) {
        let directory = folder(.experiments).appending(path: key, directoryHint: .isDirectory)
        guard var experiment = try await experiments().first(where: { $0.key == key }) else {
            throw .notFound("実験 \(key)")
        }
        try storage {
            for file in files {
                let isImage = ["png", "jpg", "jpeg", "pdf", "svg", "gif", "tiff"].contains(
                    file.pathExtension.lowercased())
                let subfolder = isImage ? "figures" : "results"
                let destination = directory.appending(path: subfolder, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                let name = uniqueName(file.lastPathComponent, in: destination)
                try copy(file, to: destination.appending(path: name))
                let relative = "\(subfolder)/\(name)"
                if isImage {
                    experiment.attachments.append(relative)
                } else if file.pathExtension.lowercased() == "csv",
                    let text = try? String(contentsOf: file, encoding: .utf8),
                    let spec = CSVTable(text).defaultSpec(file: relative)
                {
                    experiment.series.append(spec)
                } else {
                    experiment.attachments.append(relative)
                }
            }
        }
        try await saveExperiment(experiment)
    }

    // MARK: - データ、資料、ノート

    public func files(in section: LibrarySection) async throws(LibraryError) -> [LibraryFile] {
        listFiles(in: folder(section))
    }

    /// フォルダの下のファイル（隠しファイルを除く）。非同期の文脈では列挙できないので、同期の関数に分ける。
    private func listFiles(in base: URL) -> [LibraryFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let enumerator = fileManager.enumerator(
                at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        let rootPath = rootURL().standardizedFileURL.path
        var files: [LibraryFile] = []
        while let file = enumerator.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            files.append(
                LibraryFile(
                    path: relative, name: file.lastPathComponent, size: Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func importFiles(_ urls: [URL], into section: LibrarySection) async throws(LibraryError) -> [String] {
        let destination = folder(section)
        return try storage {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            return try urls.map { source in
                let name = uniqueName(source.lastPathComponent, in: destination)
                try copy(source, to: destination.appending(path: name))
                return "\(section.folder)/\(name)"
            }
        }
    }

    public func createNote(named name: String) async throws(LibraryError) -> String {
        let clean = name.trimmingCharacters(in: .whitespaces).replacing(/[\/:\\]/, with: "-")
        guard !clean.isEmpty else { throw .invalid("ノートの名前を入れてください") }
        let destination = folder(.notes)
        let fileName = uniqueName("\(clean).md", in: destination)
        try storage {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try write("# \(clean)\n\n", to: destination.appending(path: fileName))
        }
        return "\(LibrarySection.notes.folder)/\(fileName)"
    }

    public func importInbox() async throws(LibraryError) -> [String] {
        let inbox = inboxURL()
        var imported: [String] = []
        for run in subfolders(of: inbox) where exists(run.appending(path: ".complete")) {
            let runFile = run.appending(path: "run.json")
            guard let data = try? Data(contentsOf: runFile),
                let file = try? JSONDecoder().decode(ExperimentFile.self, from: data)
            else { continue }
            let key = uniqueKey(
                LibraryText.experimentKey(title: file.title, date: file.createdDate ?? .now), in: folder(.experiments))
            let destination = folder(.experiments).appending(path: key, directoryHint: .isDirectory)
            try storage {
                try fileManager.createDirectory(at: folder(.experiments), withIntermediateDirectories: true)
                try fileManager.moveItem(at: run, to: destination)
                try fileManager.moveItem(
                    at: destination.appending(path: "run.json"), to: destination.appending(path: "experiment.json"))
                try? fileManager.removeItem(at: destination.appending(path: ".complete"))
                let note = destination.appending(path: "note.md")
                if !exists(note) {
                    try write(LibraryText.experimentNote(title: file.title, body: file.note), to: note)
                }
            }
            imported.append(key)
        }
        return imported
    }

    public func delete(_ path: String) async throws(LibraryError) {
        let target = url(path).standardizedFileURL
        guard target.path.hasPrefix(rootURL().standardizedFileURL.path + "/") else { throw .invalid("ライブラリの外は消せません") }
        try storage { try fileManager.trashItem(at: target, resultingItemURL: nil) }
    }

    // MARK: - 書き出しと戻し

    public func export(to destination: URL) async throws(LibraryError) {
        try storage {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: rootURL(), to: destination)
        }
    }

    public func restore(from source: URL) async throws(LibraryError) {
        let hasLibrary = LibrarySection.allCases.contains { exists(source.appending(path: $0.folder)) }
        guard hasLibrary else { throw .invalid("選んだフォルダは sundesk のライブラリではありません") }
        let root = rootURL()
        try storage {
            if exists(root) {
                // 念のため、今のライブラリは横に残してから置き換える
                let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                    .replacing(":", with: "")
                let backup = root.deletingLastPathComponent().appending(path: "Library-\(stamp)")
                try fileManager.moveItem(at: root, to: backup)
            }
            try fileManager.copyItem(at: source, to: root)
        }
    }
}

// MARK: - 補助

extension FileSystemLibraryRepository {
    private func subfolders(of directory: URL) -> [URL] {
        ((try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func uniqueKey(_ base: String, in directory: URL) -> String {
        var key = base
        var number = 2
        while exists(directory.appending(path: key)) {
            key = "\(base)-\(number)"
            number += 1
        }
        return key
    }

    private func uniqueName(_ name: String, in directory: URL) -> String {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var number = 2
        while exists(directory.appending(path: candidate)) {
            candidate = ext.isEmpty ? "\(stem)-\(number)" : "\(stem)-\(number).\(ext)"
            number += 1
        }
        return candidate
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func copy(_ source: URL, to destination: URL) throws {
        if exists(destination) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func storage<T>(_ body: () throws -> T) throws(LibraryError) -> T {
        do {
            return try body()
        } catch let error as LibraryError {
            throw error
        } catch {
            throw .storage(error.localizedDescription)
        }
    }
}
