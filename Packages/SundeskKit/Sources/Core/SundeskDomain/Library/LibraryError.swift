//
//  LibraryError.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

public enum LibraryError: LocalizedError, Equatable, Sendable {
    /// DOI、arXiv の ID、ISBN として読めない。
    case invalidIdentifier(String)
    case notFound(String)
    case network(String)
    case storage(String)
    case unreadablePDF

    public var message: String {
        switch self {
        case .invalidIdentifier(let text): "「\(text)」は DOI、arXiv の ID、ISBN として読めませんでした"
        case .notFound(let identifier): "\(identifier) の書誌情報が見つかりませんでした"
        case .network(let reason): "書誌情報を取れませんでした: \(reason)"
        case .storage(let reason): "保存できませんでした: \(reason)"
        case .unreadablePDF: "PDF として読めませんでした"
        }
    }

    public var errorDescription: String? {
        message
    }
}
