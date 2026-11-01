//
//  BibliographyService.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 識別子から書誌情報を引く（アプリが外と通信するのはここだけ）。
public protocol BibliographyService: Sendable {
    func metadata(for identifier: ReferenceIdentifier) async throws(LibraryError) -> ReferenceMetadata
    /// 題名や著者の語で検索する（よく合う順に数件）。
    func search(_ query: String) async throws(LibraryError) -> [ReferenceMetadata]
    /// arXiv の PDF を一時フォルダに取ってくる。
    func downloadPDF(arxiv: String) async throws(LibraryError) -> URL
}
