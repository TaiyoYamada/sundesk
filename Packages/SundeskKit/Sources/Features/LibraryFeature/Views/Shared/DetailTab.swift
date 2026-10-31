//
//  DetailTab.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// 文献の詳細と、PDF を読む画面のインスペクタのタブ。
enum DetailTab: String, CaseIterable, Identifiable {
    case info
    case annotations
    case note
    case summary

    var id: Self { self }

    var title: String {
        switch self {
        case .info: "情報"
        case .annotations: "注釈"
        case .note: "メモ"
        case .summary: "要約"
        }
    }
}
