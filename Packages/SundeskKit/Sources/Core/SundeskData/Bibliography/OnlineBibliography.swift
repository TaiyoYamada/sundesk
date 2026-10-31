//
//  OnlineBibliography.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 書誌情報を、doi.org（DOI）、arXiv の API、Open Library（ISBN）から引く。アプリが外と通信するのはここだけ。
public struct OnlineBibliography: BibliographyService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func metadata(for identifier: ReferenceIdentifier) async throws(LibraryError) -> ReferenceMetadata {
        switch identifier {
        case .doi(let doi):
            // arXiv が振った DOI は、arXiv の API のほうが詳しい（要旨や、出版された先の DOI がある）
            if let match = doi.wholeMatch(of: /(?i)10\.48550\/arxiv\.(.+)/) {
                return try await metadata(for: .arxiv(String(match.output.1)))
            }
            let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
            let data = try await fetch(
                "https://doi.org/\(encoded)", accept: "application/vnd.citationstyles.csl+json")
            guard var metadata = CSLItem.parse(data) else { throw .notFound(identifier.text) }
            if metadata.doi.isEmpty { metadata.doi = doi }
            return metadata
        case .arxiv(let id):
            let data = try await fetch("https://export.arxiv.org/api/query?id_list=\(id)")
            guard let metadata = ArxivFeed.parse(data, id: id) else { throw .notFound(identifier.text) }
            return metadata
        case .isbn(let isbn):
            let data = try await fetch("https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")
            guard let metadata = OpenLibraryBook.parse(data, isbn: isbn) else { throw .notFound(identifier.text) }
            return metadata
        }
    }

    public func downloadPDF(arxiv: String) async throws(LibraryError) -> URL {
        let data = try await fetch("https://arxiv.org/pdf/\(arxiv)")
        let name = arxiv.replacing("/", with: "_")
        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: "\(name).pdf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            throw .storage(error.localizedDescription)
        }
        return url
    }

    private func fetch(_ address: String, accept: String? = nil) async throws(LibraryError) -> Data {
        guard let url = URL(string: address) else { throw .invalidIdentifier(address) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Crossref と Open Library の決まりに従い、身元を名乗る
        request.setValue("sundesk (personal reference manager; macOS)", forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw .network(status == 404 ? "見つかりませんでした" : "応答が \(status) でした")
        }
        return data
    }
}

/// 書誌情報の文字に混ざった HTML や JATS のタグと文字参照を外し、空白をまとめる。
enum BibliographyText {
    static func clean(_ text: String) -> String {
        text.replacing(/<[^>]+>/, with: " ")
            .replacing("&amp;", with: "&")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&quot;", with: "\"")
            .replacing("&#39;", with: "'")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
