//
//  PDFKitReader.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import PDFKit
import SundeskDomain

/// PDFKit で PDF の文字を読む。
public struct PDFKitReader: PDFReading {
    public init() {}

    public func identifier(in pdf: URL) -> ReferenceIdentifier? {
        guard let document = PDFDocument(url: pdf) else { return nil }
        for index in 0..<min(document.pageCount, 3) {
            guard let text = document.page(at: index)?.string else { continue }
            // arXiv の PDF は、余白に「arXiv:1304.3061v1」と縦書きで入っている
            if let match = text.firstMatch(of: /arXiv:(\d{4}\.\d{4,5})/) { return .arxiv(String(match.output.1)) }
            if let match = text.firstMatch(of: /(?i)(?:doi[:\s]*|doi\.org\/)(10\.\d{4,9}\/[^\s"<>]+)/) {
                return ReferenceIdentifier(parsing: String(match.output.1))
            }
        }
        return nil
    }

    public func title(in pdf: URL) -> String? {
        guard let document = PDFDocument(url: pdf) else { return nil }
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, title.count > 8 {
            return title
        }
        return document.page(at: 0)?.string?.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 15 && !$0.lowercased().contains("arxiv") }
    }

    public func pages(of pdf: URL) -> [String] {
        guard let document = PDFDocument(url: pdf) else { return [] }
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }
}
