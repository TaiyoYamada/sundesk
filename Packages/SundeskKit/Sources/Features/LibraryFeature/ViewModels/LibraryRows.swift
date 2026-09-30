//
//  LibraryRows.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// ~/Research の実験のプロジェクト（一覧の 1 節）。
public struct ResearchProjectRow: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let runs: [ResearchRunRow]

    init(_ project: ResearchProject) {
        path = project.path
        title = project.title
        runs = project.runs.map(ResearchRunRow.init)
    }

    init(path: String, title: String, runs: [ResearchRunRow]) {
        self.path = path
        self.title = title
        self.runs = runs
    }
}

/// 木の中で 1 つのものとして見せるフォルダ。
public struct LibraryBundle: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case paper(key: String)
        case experiment(key: String)
        case researchProject(path: String)
        case researchRun(path: String)
    }

    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    /// 中を見せないか（論文、実験、実行）。プロジェクトは中も見せる。
    public let isLeaf: Bool

    /// 開く先。
    public var destination: LibraryDestination {
        switch kind {
        case .paper(let key): .paper(key: key, title: title)
        case .experiment(let key): .experiment(key: key, title: title)
        case .researchProject(let path): .researchProject(path: path, title: title)
        case .researchRun(let path): .researchRun(path: path, title: title)
        }
    }
}
