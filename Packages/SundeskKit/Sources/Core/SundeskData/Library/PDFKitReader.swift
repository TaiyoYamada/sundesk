//
//  PDFKitReader.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
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

    public func titleCandidates(in pdf: URL) -> [String] {
        guard let document = PDFDocument(url: pdf) else { return [] }
        var candidates = (0..<min(document.pageCount, 2)).compactMap { document.page(at: $0).flatMap(largestText) }
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            candidates.append(title)
        }
        var seen: Set<String> = []
        return candidates.map { BibliographyText.joiningCJK(BibliographyText.clean($0)) }
            .filter { PaperTitle.isPlausible($0) && seen.insert($0).inserted }
    }

    /// ページでいちばん大きい文字のまとまり（題名はたいていこれ）。題名らしくなければ、次に大きい文字を見る。
    private func largestText(on page: PDFPage) -> String? {
        guard let text = page.attributedString, text.length > 0 else { return nil }
        var runs: [(text: String, size: CGFloat)] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? 0
            runs.append(((text.string as NSString).substring(with: range), size))
        }
        let sizes = Set(runs.filter { $0.text.contains(where: \.isLetter) }.map(\.size)).sorted(by: >)
        for size in sizes.prefix(4) {
            // その大きさの文字が最初に出てくるところから、大きさが変わるまでをつなぐ（空白や改行は挟んでよい）
            guard let start = runs.firstIndex(where: { $0.size == size && $0.text.contains(where: \.isLetter) })
            else { continue }
            var block = ""
            for run in runs[start...] {
                guard run.size == size || run.text.allSatisfy(\.isWhitespace) else { break }
                block += run.text
            }
            let cleaned = BibliographyText.joiningCJK(BibliographyText.clean(block))
            if PaperTitle.isPlausible(cleaned) { return cleaned }
        }
        return nil
    }

    public func pages(of pdf: URL) -> [String] {
        guard let document = PDFDocument(url: pdf) else { return [] }
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }
}
