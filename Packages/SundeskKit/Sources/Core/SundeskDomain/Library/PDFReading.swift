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
    /// 題名の候補（確からしい順）。1 ページ目でいちばん大きい文字、2 ページ目のそれ（1 ページ目が表紙のとき）、
    /// PDF に埋め込まれた題名の順に並べ、題名としてありえないもの（``PaperTitle/isPlausible(_:)``）は除く。
    func titleCandidates(in pdf: URL) -> [String]
    /// ページごとの文字。読めなければ空。
    func pages(of pdf: URL) -> [String]
}
