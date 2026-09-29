//
//  PaperViewModel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 1 本の論文。書誌情報と読んだ状態を直し、PDF を開く。
@MainActor
@Observable
public final class PaperViewModel {
    public let key: String
    public var title = ""
    /// 著者（「, 」で区切る）。
    public var authors = ""
    public var year = ""
    public var venue = ""
    public var arxiv = ""
    public var doi = ""
    public var url = ""
    public var status = ReadingStatus.unread.rawValue
    /// タグ（「, 」で区切る）。
    public var tags = ""
    public private(set) var pdfURL: URL?
    public private(set) var notePath = ""
    public private(set) var isLoaded = false
    public private(set) var isWorking = false
    public var errorMessage: String?

    @ObservationIgnored private let library: any ManageLibraryUseCase
    @ObservationIgnored private var paper: Paper?

    public init(key: String, library: any ManageLibraryUseCase) {
        self.key = key
        self.library = library
    }

    public func load() async {
        guard let paper = try? await library.papers().first(where: { $0.key == key }) else {
            errorMessage = "論文が見つかりません（\(key)）"
            return
        }
        apply(paper)
    }

    private func apply(_ paper: Paper) {
        self.paper = paper
        title = paper.metadata.title
        authors = paper.metadata.authors.joined(separator: ", ")
        year = paper.metadata.year.map(String.init) ?? ""
        venue = paper.metadata.venue ?? ""
        arxiv = paper.metadata.arxiv ?? ""
        doi = paper.metadata.doi ?? ""
        url = paper.metadata.url ?? ""
        status = paper.status.rawValue
        tags = paper.tags.joined(separator: ", ")
        pdfURL = paper.pdfPath.map { library.fileURL(for: $0) }
        notePath = paper.notePath
        isLoaded = true
    }

    /// 入力した書誌情報を保存する。
    public func save() async {
        guard var paper else { return }
        paper.metadata = PaperMetadata(
            title: title.trimmingCharacters(in: .whitespaces), authors: Self.split(authors), year: Int(year),
            venue: venue.nilIfBlank, arxiv: arxiv.nilIfBlank, doi: doi.nilIfBlank, url: url.nilIfBlank)
        paper.status = ReadingStatus(rawValue: status) ?? .unread
        paper.tags = Self.split(tags)
        do {
            try await library.savePaper(paper)
            self.paper = paper
        } catch {
            errorMessage = error.message
        }
    }

    /// arXiv や Crossref から書誌情報を取り直す。
    public func refresh() async {
        guard let paper else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            apply(try await library.refreshMetadata(of: paper))
        } catch {
            errorMessage = error.message
        }
    }

    public func attachPDF(_ url: URL) async {
        guard let paper else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try await library.attachPDF(url, to: paper)
            await load()
        } catch {
            errorMessage = error.message
        }
    }

    /// 引用のための文字列（BibTeX）。
    public var bibtex: String {
        let firstAuthor = Self.split(authors).first?.split(separator: " ").last.map(String.init) ?? "anon"
        var fields = ["title = {\(title)}", "author = {\(Self.split(authors).joined(separator: " and "))}"]
        if !year.isEmpty { fields.append("year = {\(year)}") }
        if !venue.isEmpty { fields.append("journal = {\(venue)}") }
        if !doi.isEmpty { fields.append("doi = {\(doi)}") }
        if !arxiv.isEmpty { fields.append("eprint = {\(arxiv)}, archivePrefix = {arXiv}") }
        return "@article{\(firstAuthor.lowercased())\(year),\n  " + fields.joined(separator: ",\n  ") + "\n}"
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
