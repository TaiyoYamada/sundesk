//
//  FileSystemResearchProjects.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// ~/Research/experiment のプロジェクトと実行を、ファイルシステムから見つける（読むだけ）。
///
/// 実行の形はプロジェクトごとに違うので、決まった形は求めない。
/// `config.json` か CSV のあるフォルダを 1 回の実行とみなし、その下のフォルダ（figures/、tables/ など）は実行の一部とする。
public struct FileSystemResearchProjects: ResearchProjectRepository {
    private let mounts: @Sendable () -> [VaultMount]

    public init(mounts: @escaping @Sendable () -> [VaultMount]) {
        self.mounts = mounts
    }

    /// 実験のプロジェクトを置くフォルダ（~/Research の中）。
    static let experimentFolders = ["experiment", "experiments"]
    /// 実行を探さないフォルダ（コードや文書、依存ライブラリ）。
    static let skippedFolders: Set<String> = [
        "notebooks", "docs", "paper", "papers", "src", "scripts", "tests", "code", "node_modules", "__pycache__",
        "slides", "original", "notes",
    ]
    static let figureExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp"]

    @concurrent
    public func projects() async -> [ResearchProject] {
        guard let research = mounts().first(where: { $0.name == ResearchSources.researchName }) else { return [] }
        return Self.scan(research)
    }

    static func scan(_ research: VaultMount) -> [ResearchProject] {
        var projects: [ResearchProject] = []
        for folder in experimentFolders {
            let base = research.url.appending(path: folder, directoryHint: .isDirectory)
            for directory in subdirectories(of: base) {
                let name = directory.lastPathComponent
                let path = "\(research.name)/\(folder)/\(name)"
                projects.append(project(at: directory, name: name, path: path))
            }
        }
        return projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func project(at directory: URL, name: String, path: String) -> ResearchProject {
        let readme = directory.appending(path: "README.md")
        let (title, summary) = readmeHeading((try? String(contentsOf: readme, encoding: .utf8)) ?? "")
        var documents: [String] = FileManager.default.fileExists(atPath: readme.path) ? ["\(path)/README.md"] : []
        let docs = directory.appending(path: "docs", directoryHint: .isDirectory)
        documents += files(in: docs).filter { $0.pathExtension.lowercased() == "md" }
            .map { "\(path)/docs/\($0.lastPathComponent)" }
        var runs: [ResearchRun] = []
        collectRuns(in: directory, relative: "", project: (name, path), depth: 0, into: &runs)
        runs.sort { ($0.date ?? .distantPast, $0.relativePath) > ($1.date ?? .distantPast, $1.relativePath) }
        return ResearchProject(
            name: name, path: path, title: title ?? name, summary: summary, documents: documents, runs: runs)
    }

    /// 実行を探す。見つけたら、その下は探さない。
    /// - Parameter project: プロジェクトのフォルダ名と、ライブラリの中でのパス。
    private static func collectRuns(
        in directory: URL, relative: String, project: (name: String, path: String), depth: Int,
        into runs: inout [ResearchRun]
    ) {
        guard depth <= 5 else { return }
        for child in subdirectories(of: directory) {
            let name = child.lastPathComponent
            guard !skippedFolders.contains(name) else { continue }
            let childRelative = relative.isEmpty ? name : "\(relative)/\(name)"
            let contents = files(in: child)
            let isRun =
                contents.contains { $0.lastPathComponent == "config.json" }
                || contents.contains { $0.pathExtension.lowercased() == "csv" }
            if isRun {
                runs.append(run(at: child, relative: childRelative, project: project.name, projectPath: project.path))
            } else {
                collectRuns(in: child, relative: childRelative, project: project, depth: depth + 1, into: &runs)
            }
        }
    }

    static func run(at directory: URL, relative: String, project: String, projectPath: String) -> ResearchRun {
        let path = "\(projectPath)/\(relative)"
        var tables: [ResearchFile] = []
        var figures: [String] = []
        var notes: [String] = []
        let root = directory.standardizedFileURL.path
        if let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])
        {
            while let file = enumerator.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let inside = String(file.standardizedFileURL.path.dropFirst(root.count + 1))
                switch file.pathExtension.lowercased() {
                case "csv":
                    tables.append(ResearchFile(path: "\(path)/\(inside)", name: inside, size: values?.fileSize ?? 0))
                case let ext where figureExtensions.contains(ext): figures.append("\(path)/\(inside)")
                case "md": notes.append("\(path)/\(inside)")
                default: break
                }
            }
        }
        let config = directory.appending(path: "config.json")
        let parameters = (try? Data(contentsOf: config)).map(flattenedJSON) ?? [:]
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        return ResearchRun(
            path: path, project: project, relativePath: relative,
            date: date(fromFolderName: directory.lastPathComponent) ?? attributes?[.modificationDate] as? Date,
            parameters: parameters,
            tables: tables.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            figures: figures.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            notes: notes.sorted())
    }

    // MARK: - 読み取り

    /// README の最初の見出しと、その次の段落。
    static func readmeHeading(_ source: String) -> (title: String?, summary: String?) {
        var title: String?
        var paragraph: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if title == nil {
                if trimmed.hasPrefix("# ") { title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if trimmed.isEmpty {
                if !paragraph.isEmpty { break }
                continue
            }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("|") || trimmed.hasPrefix("```") {
                if !paragraph.isEmpty { break }
                continue
            }
            paragraph.append(trimmed)
        }
        let summary = paragraph.joined(separator: " ").replacing("**", with: "")
        return (title, summary.isEmpty ? nil : summary)
    }

    /// フォルダ名に書かれた日時（`2026-01-02_030405`、`20260102_030405_tag`、`2026-01-02_0304` など）。
    static func date(fromFolderName name: String) -> Date? {
        guard
            let match = name.firstMatch(
                of: /^(\d{4})-?(\d{2})-?(\d{2})(?:[_T-](\d{2})(\d{2})(\d{2})?)?/)
        else { return nil }
        var components = DateComponents()
        components.year = Int(match.1)
        components.month = Int(match.2)
        components.day = Int(match.3)
        components.hour = match.4.flatMap { Int($0) } ?? 0
        components.minute = match.5.flatMap { Int($0) } ?? 0
        components.second = match.6.flatMap { Int($0) } ?? 0
        guard let month = components.month, (1...12).contains(month), let day = components.day, (1...31).contains(day)
        else { return nil }
        return Calendar.current.date(from: components)
    }

    /// JSON を平らな設定にする（`{"a": {"b": 1}}` → `a.b = 1`、配列は `1, 2, 3`）。
    static func flattenedJSON(_ data: Data) -> [String: ParameterValue] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: ParameterValue] = [:]
        func visit(_ value: Any, key: String) {
            switch value {
            case let dictionary as [String: Any]:
                for (child, value) in dictionary { visit(value, key: key.isEmpty ? child : "\(key).\(child)") }
            case let array as [Any]:
                result[key] = .text(array.map { scalarText($0) }.joined(separator: ", "))
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                result[key] = .flag(number.boolValue)
            case let number as NSNumber:
                result[key] = .number(number.doubleValue)
            case let text as String:
                result[key] = .text(text)
            default:
                break
            }
        }
        visit(object, key: "")
        return result
    }

    private static func scalarText(_ value: Any) -> String {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            number.boolValue ? "true" : "false"
        case let number as NSNumber: ParameterValue.number(number.doubleValue).description
        case let text as String: text
        default: "…"
        }
    }

    // MARK: - ファイル

    /// 中のフォルダ（隠しフォルダとシンボリックリンクは除く）。
    static func subdirectories(of directory: URL) -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])) ?? []
        return urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 中のファイル（フォルダは除く）。
    static func files(in directory: URL) -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
    }
}
