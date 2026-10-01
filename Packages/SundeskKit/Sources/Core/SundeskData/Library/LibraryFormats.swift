//
//  LibraryFormats.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain

// ライブラリのファイルの形（docs/library-format.md）を読み書きする。

// MARK: - experiment.json

/// JSON の値（パラメータに文字、数、真偽が混ざる）。
enum JSONScalar: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string((try? container.decode(String.self)) ?? "")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    var parameter: ParameterValue {
        switch self {
        case .string(let value): .text(value)
        case .number(let value): .number(value)
        case .bool(let value): .flag(value)
        }
    }

    init(_ value: ParameterValue) {
        switch value {
        case .text(let text): self = .string(text)
        case .number(let number): self = .number(number)
        case .flag(let flag): self = .bool(flag)
        }
    }
}

struct ExperimentFile: Codable {
    struct ObjectiveFile: Codable {
        var name: String
        var direction: String?
        var reference: Double?
    }

    struct SeriesFile: Codable {
        var file: String
        var x: String
        var y: [String]
    }

    var title: String
    var algorithm: String?
    var problem: String?
    var status: String?
    var created: String?
    var finished: String?
    var tags: [String]?
    var parameters: [String: JSONScalar]?
    var seed: Int?
    var seeds: [Int]?
    var objective: ObjectiveFile?
    var metrics: [String: Double]?
    var series: [SeriesFile]?
    var attachments: [String]?
    var links: [String]?
    /// 記録用ライブラリが書く、note.md にする文章。
    var note: String?

    var createdDate: Date? { created.flatMap(Self.date) }

    func experiment(key: String) -> ResearchExperiment {
        ResearchExperiment(
            key: key, title: title, algorithm: algorithm ?? "", problem: problem ?? "",
            status: status.flatMap(ExperimentStatus.init) ?? .done, created: createdDate,
            finished: finished.flatMap(Self.date), tags: tags ?? [],
            parameters: (parameters ?? [:]).mapValues(\.parameter), seeds: seeds ?? seed.map { [$0] } ?? [],
            objective: objective.map {
                Objective(name: $0.name, minimizes: $0.direction != "maximize", reference: $0.reference)
            },
            metrics: metrics ?? [:], series: (series ?? []).map { SeriesSpec(file: $0.file, x: $0.x, y: $0.y) },
            attachments: attachments ?? [], links: links ?? [])
    }

    init(_ experiment: ResearchExperiment) {
        title = experiment.title
        algorithm = experiment.algorithm
        problem = experiment.problem
        status = experiment.status.rawValue
        created = experiment.created.map(Self.string)
        finished = experiment.finished.map(Self.string)
        tags = experiment.tags
        parameters = experiment.parameters.mapValues(JSONScalar.init)
        if experiment.seeds.count == 1 {
            seed = experiment.seeds[0]
        } else if !experiment.seeds.isEmpty {
            seeds = experiment.seeds
        }
        objective = experiment.objective.map {
            ObjectiveFile(name: $0.name, direction: $0.minimizes ? "minimize" : "maximize", reference: $0.reference)
        }
        metrics = experiment.metrics
        series = experiment.series.map { SeriesFile(file: $0.file, x: $0.x, y: $0.y) }
        attachments = experiment.attachments
        links = experiment.links
    }

    static func date(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
            ?? (try? Date.ISO8601FormatStyle().year().month().day().parse(text))
    }

    static func string(_ date: Date) -> String {
        date.formatted(
            .localISO8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))
    }
}

// MARK: - CSV

/// 1 行目が列名、2 行目からが数の CSV。
struct CSVTable {
    let header: [String]
    let rows: [[String]]

    init(_ text: String) {
        var lines = text.split(whereSeparator: \.isNewline).map {
            $0.split(separator: ",", omittingEmptySubsequences: false)
        }
        header = lines.isEmpty ? [] : lines.removeFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        rows = lines.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    func column(_ name: String) -> [Double]? {
        guard let index = header.firstIndex(of: name) else { return nil }
        return rows.map { index < $0.count ? Double($0[index]) ?? .nan : .nan }
    }

    func series(_ spec: SeriesSpec) -> SeriesData? {
        let x = column(spec.x) ?? rows.indices.map(Double.init)
        var columns: [String: [Double]] = [:]
        for name in spec.y {
            if let values = column(name) { columns[name] = values }
        }
        return columns.isEmpty ? nil : SeriesData(spec: spec, x: x, columns: columns)
    }

    /// 取り込んだ CSV の既定の描き方。反復らしい列を x に、残りの数の列（3 つまで）を y にする。
    func defaultSpec(file: String) -> SeriesSpec? {
        let numeric = header.filter { name in column(name)?.contains { !$0.isNaN } == true }
        guard !numeric.isEmpty else { return nil }
        let xNames = ["iteration", "iter", "step", "generation", "epoch", "evaluations", "time", "t"]
        let x = numeric.first { xNames.contains($0.lowercased()) } ?? numeric[0]
        let y = numeric.filter { $0 != x }.prefix(3)
        guard !y.isEmpty else { return nil }
        return SeriesSpec(file: file, x: x, y: Array(y))
    }
}

// MARK: - Markdown の文章

enum LibraryText {
    /// note.md のフロントマターから、論文を読む。
    static func paper(key: String, properties: [NoteProperty], hasPDF: Bool) -> Paper? {
        var values: [String: PropertyValue] = [:]
        for property in properties { values[property.key] = property.value }
        func text(_ key: String) -> String? {
            switch values[key] {
            case .text(let value): value.isEmpty ? nil : value
            case .list(let items): items.first
            case nil: nil
            }
        }
        func list(_ key: String) -> [String] {
            switch values[key] {
            case .list(let items): items
            case .text(let value):
                value.isEmpty ? [] : value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case nil: []
            }
        }
        guard text("type") == "paper" || values["title"] != nil else { return nil }
        let metadata = PaperMetadata(
            title: text("title") ?? key, authors: list("authors"), year: text("year").flatMap(Int.init),
            venue: text("venue"), arxiv: text("arxiv"), doi: text("doi"), url: text("url"))
        // 写した PDF（paper.pdf）があればそれを、なければ論文メモの pdf が指す PDF（~/Research など）を使う
        let linked = text("pdf")
        return Paper(
            key: key, metadata: metadata, status: text("status").flatMap(ReadingStatus.init) ?? .unread,
            tags: list("tags"), added: text("added").flatMap(ExperimentFile.date),
            pdfPath: hasPDF ? "\(LibrarySection.papers.folder)/\(key)/paper.pdf" : linked, linkedPDF: linked)
    }

    /// 論文のフロントマター。
    static func frontmatter(for paper: Paper) -> String {
        var lines = ["---", "type: paper", "title: \(quote(paper.metadata.title))"]
        lines.append("authors: [\(paper.metadata.authors.map(quote).joined(separator: ", "))]")
        if let year = paper.metadata.year { lines.append("year: \(year)") }
        if let venue = paper.metadata.venue { lines.append("venue: \(quote(venue))") }
        if let arxiv = paper.metadata.arxiv { lines.append("arxiv: \(quote(arxiv))") }
        if let doi = paper.metadata.doi { lines.append("doi: \(quote(doi))") }
        if let url = paper.metadata.url { lines.append("url: \(quote(url))") }
        if let linked = paper.linkedPDF { lines.append("pdf: \(quote(linked))") }
        lines.append("status: \(paper.status.rawValue)")
        lines.append("tags: [\(paper.tags.map(quote).joined(separator: ", "))]")
        let added = paper.added ?? .now
        lines.append("added: \(added.formatted(.localISO8601.year().month().day()))")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    /// フロントマターを除いた本文。
    static func body(of source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return source }
        return lines[(end + 1)...].joined(separator: "\n")
    }

    static func experimentNote(title: String, body: String?) -> String {
        "---\ntype: experiment\ntitle: \(quote(title))\n---\n# \(title)\n\n"
            + (body.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" } ?? "## 仮説\n\n## 考察\n")
    }

    /// 論文のキー（例: `peruzzo2014-variational`）。英字が取れなければ arXiv の ID か DOI から作る。
    static func paperKey(for metadata: PaperMetadata) -> String {
        let lastName = metadata.authors.first?.split(separator: " ").last.map(String.init) ?? ""
        let word =
            metadata.title.split(separator: " ").map(String.init)
            .first { $0.count > 3 && !["the", "with", "from", "into", "using", "towards"].contains($0.lowercased()) }
            ?? ""
        let base =
            slug(lastName) + (metadata.year.map(String.init) ?? "") + (slug(word).isEmpty ? "" : "-" + slug(word))
        if slug(lastName).isEmpty {
            if let arxiv = metadata.arxiv { return "arxiv-" + slug(arxiv) }
            if let doi = metadata.doi { return "doi-" + slug(doi) }
            // 著者も ID もなければ、題名の初めの語から作る（日本語はローマ字にする）
            let words = slug(romanized(metadata.title)).split(separator: "-").prefix(4).joined(separator: "-")
            if !words.isEmpty { return String(words.prefix(48)) }
            let day = Date.now.formatted(
                .localISO8601.year().month().day().dateSeparator(.omitted))
            return "paper-" + day
        }
        return base
    }

    /// 実験のキー（`YYYY-MM-DD-<題名から作った名前>`）。
    static func experimentKey(title: String, date: Date) -> String {
        let day = date.formatted(.localISO8601.year().month().day())
        let name = slug(title)
        return name.isEmpty ? "\(day)-experiment" : "\(day)-\(name.prefix(40))"
    }

    /// 英数字と `-` だけの名前。
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        let replaced = folded.lowercased().replacing(/[^a-z0-9.]+/, with: "-")
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }

    /// 日本語などを、キーに使えるローマ字にする。
    static func romanized(_ text: String) -> String {
        text.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? text
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}
