//
//  AttachmentStore.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 添付する PDF を、アプリの保存先のフォルダに置く。
public protocol AttachmentStore: Sendable {
    /// 保存先のフォルダ。
    var root: URL { get }
    /// PDF を写す。保存先のフォルダからのパスを返す。
    func importPDF(_ source: URL, for referenceID: UUID) throws(LibraryError) -> String
    func url(for path: String) -> URL
    /// その文献の添付を、すべて消す。
    func removeAttachments(of referenceID: UUID) throws(LibraryError)
}
