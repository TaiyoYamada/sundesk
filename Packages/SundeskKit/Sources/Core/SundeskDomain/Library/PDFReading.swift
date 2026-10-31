//
//  PDFReading.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// PDF の中身を読む。
public protocol PDFReading: Sendable {
    /// 最初の数ページに書かれた DOI か arXiv の ID。
    func identifier(in pdf: URL) -> ReferenceIdentifier?
    /// PDF の属性か 1 ページ目から推し量った題名。
    func title(in pdf: URL) -> String?
    /// ページごとの文字。読めなければ空。
    func pages(of pdf: URL) -> [String]
}
