//
//  DetailTab.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// PDF の横のインスペクタのタブ。
public enum DetailTab: String, CaseIterable, Identifiable, Sendable {
    case info
    case annotations
    case note
    case summary

    public var id: Self { self }

    var title: String {
        switch self {
        case .info: "情報"
        case .annotations: "注釈"
        case .note: "メモ"
        case .summary: "要約"
        }
    }
}
