//
//  OnlineBibliography.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import PDFKit
import SundeskDomain

/// 論文の書誌情報を、arXiv の API と Crossref の API から取る。アプリが外と通信するのはここだけ。
public struct OnlineBibliography: BibliographyService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func metadata(for identifier: PaperIdentifier) async throws(LibraryError) -> PaperMetadata {
        switch identifier {
        case .arxiv(let id):
            let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(id)")!
            let data = try await fetch(url)
            guard let metadata = ArxivFeed.parse(data, id: id) else { throw .notFound("arXiv:\(id)") }
            return metadata
        case .doi(let doi):
            let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
            let url = URL(string: "https://api.crossref.org/works/\(encoded)")!
            let data = try await fetch(url)
            guard let metadata = CrossrefWork.parse(data, doi: doi) else { throw .notFound("DOI \(doi)") }
            return metadata
        }
    }

    public func downloadPDF(arxiv: String) async throws(LibraryError) -> URL {
        let data = try await fetch(URL(string: "https://arxiv.org/pdf/\(arxiv)")!)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(arxiv)-\(UUID().uuidString).pdf")
        do {
            try data.write(to: url)
        } catch {
            throw .storage(error.localizedDescription)
        }
        return url
    }

    private func fetch(_ url: URL) async throws(LibraryError) -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Crossref の決まりに従い、身元を名乗る
        request.setValue("sundesk (personal research library; macOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw LibraryError.network(status == 404 ? "見つかりませんでした" : "応答が \(status) でした")
            }
            return data
        } catch let error as LibraryError {
            throw error
        } catch {
            throw .network(error.localizedDescription)
        }
    }
}

// MARK: - arXiv（Atom の XML）

enum ArxivFeed {
    static func parse(_ data: Data, id: String) -> PaperMetadata? {
        let delegate = ArxivParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let title = delegate.title else { return nil }
        let year = delegate.published.flatMap { Int($0.prefix(4)) }
        return PaperMetadata(
            title: clean(title), authors: delegate.authors.map(clean), year: year,
            venue: delegate.journal.map(clean), arxiv: id, doi: delegate.doi,
            url: "https://arxiv.org/abs/\(id)", abstract: delegate.summary.map(clean))
    }

    static func clean(_ text: String) -> String {
        text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ArxivParserDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var summary: String?
    var published: String?
    var doi: String?
    var journal: String?
    var authors: [String] = []
    private var inEntry = false
    private var inAuthor = false
    private var text = ""

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if elementName == "entry" { inEntry = true }
        if elementName == "author" { inAuthor = true }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard inEntry else { return }
        switch elementName {
        case "title": title = text
        case "summary": summary = text
        case "published": published = text
        case "name" where inAuthor: authors.append(text)
        case "author": inAuthor = false
        case "arxiv:doi", "doi": doi = ArxivFeed.clean(text)
        case "arxiv:journal_ref", "journal_ref": journal = text
        case "entry": inEntry = false
        default: break
        }
    }
}

// MARK: - Crossref（JSON）

private struct CrossrefAuthor: Decodable {
    let given: String?
    let family: String?
    let name: String?
}

private struct CrossrefDate: Decodable {
    let dateParts: [[Int?]]?

    private enum CodingKeys: String, CodingKey {
        case dateParts = "date-parts"
    }
}

private struct CrossrefMessage: Decodable {
    let title: [String]?
    let author: [CrossrefAuthor]?
    let containerTitle: [String]?
    let issued: CrossrefDate?
    let link: String?
    let abstract: String?

    private enum CodingKeys: String, CodingKey {
        case title, author, issued, abstract
        case containerTitle = "container-title"
        case link = "URL"
    }
}

private struct CrossrefResponse: Decodable {
    let message: CrossrefMessage
}

enum CrossrefWork {
    static func parse(_ data: Data, doi: String) -> PaperMetadata? {
        guard let message = try? JSONDecoder().decode(CrossrefResponse.self, from: data).message,
            let title = message.title?.first
        else { return nil }
        let authors = (message.author ?? []).compactMap { author -> String? in
            if let name = author.name { return name }
            return [author.given, author.family].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        }
        let year = message.issued?.dateParts?.first?.first.flatMap { $0 }
        return PaperMetadata(
            title: ArxivFeed.clean(title), authors: authors, year: year, venue: message.containerTitle?.first,
            doi: doi, url: message.link ?? "https://doi.org/\(doi)",
            abstract: message.abstract.map { ArxivFeed.clean($0.replacing(/<[^>]+>/, with: "")) })
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - PDF

/// PDF の最初の数ページから、arXiv の ID や DOI、題名を読む。
public struct PDFKitInspector: PDFInspecting {
    public init() {}

    public func identifier(in pdf: URL) -> PaperIdentifier? {
        guard let document = PDFDocument(url: pdf) else { return nil }
        for index in 0..<min(document.pageCount, 3) {
            guard let text = document.page(at: index)?.string else { continue }
            // arXiv の PDF は、余白に「arXiv:1304.3061v1」と縦書きで入っている
            if let match = text.firstMatch(of: /arXiv:(\d{4}\.\d{4,5})/) { return .arxiv(String(match.output.1)) }
            if let match = text.firstMatch(of: /(?i)doi[:\s]*(10\.\d{4,9}\/[^\s"<>]+)/) {
                return PaperIdentifier(parsing: String(match.output.1))
            }
        }
        return nil
    }

    public func title(in pdf: URL) -> String? {
        guard let document = PDFDocument(url: pdf) else { return nil }
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
            title.count > 8
        {
            return title
        }
        return document.page(at: 0)?.string?.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 15 && !$0.lowercased().contains("arxiv") }
    }
}
