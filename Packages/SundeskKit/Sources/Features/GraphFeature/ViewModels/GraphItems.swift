//
//  GraphItems.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

// MARK: - 表示用の型

/// グラフの点。
public struct GraphNodeItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let radius: Double
    public let community: Int
    /// まとまりの番号（大きい順に 0 から）。色に使う。
    public let group: Int
    /// 生まれた時（0〜1。ノートを作った順）。分からなければ nil。
    public let birth: Double?
}

/// グラフの線（`nodes` の添字でつなぐ）。
public struct GraphEdgeItem: Hashable, Sendable {
    public let source: Int
    public let target: Int
    public let weight: Double
}

/// 分野のまとまり。
public struct CommunityItem: Identifiable, Hashable, Sendable {
    public let id: Int
    /// まとまりの番号（大きい順に 0 から）。色に使う。
    public let group: Int
    public let size: Int
    public let topLabels: [String]

    /// まとまりの名前（中心的な概念を 2 つ）。
    public var name: String { topLabels.prefix(2).joined(separator: "・") }
}

/// 経路の 1 歩。
public struct PathStepItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let group: Int
}

/// 時間の再生の目盛り（ノートを作った順）。
public struct TimelineStepItem: Hashable, Sendable {
    public let title: String
    public let date: String

    init(_ note: KnowledgeTimeline.Note) {
        title = note.title
        date = note.date.formatted(
            .dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "ja_JP")))
    }
}

/// 選んだ概念の詳細。
public struct ConceptDetailItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let community: Int
    /// まとまりの番号（色に使う）。
    public let group: Int
    public let importance: String
    public let frequency: Int
    public let related: [RelatedConceptItem]
    public let sources: [ConceptSourceItem]

    init(concept: Concept, group: Int, related: [RelatedConceptItem], sources: [ConceptSourceItem]) {
        id = concept.id
        label = concept.label
        community = concept.community
        self.group = group
        importance = String(format: "%.4f", concept.pagerank)
        frequency = concept.frequency
        self.related = related
        self.sources = sources
    }
}

public struct RelatedConceptItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    /// 関係の種類（「共起」「定義」など）。
    public let kinds: String

    init(_ related: RelatedConcept) {
        id = related.concept.id
        label = related.concept.label
        kinds = related.kinds.map(\.title).joined(separator: "・")
    }
}

public struct ConceptSourceItem: Identifiable, Hashable, Sendable {
    public var id: String { chunkID }
    public let chunkID: String
    public let path: String
    public let title: String
    /// 見出しの階層（ノートのタイトルを除く）。
    public let heading: String
    public let line: Int
    public let snippet: String

    init(_ source: ConceptSource) {
        chunkID = source.chunk.id
        path = source.chunk.notePath
        title = source.chunk.noteTitle
        heading = source.chunk.headingPath.dropFirst().joined(separator: " › ")
        line = source.chunk.line
        snippet = String(source.chunk.plainText.replacing(/\s+/, with: " ").prefix(80))
    }
}

/// 知識の作り直しの進み具合。
public struct KnowledgeBuildItem: Hashable, Sendable {
    public let title: String
    /// 0〜1。分からなければ nil。
    public let fraction: Double?

    init?(_ step: KnowledgeBuildStep) {
        switch step {
        case .readingNotes(let done, let total):
            title = "ノートを読んでいます（\(done)/\(total)）"
            fraction = total == 0 ? nil : Double(done) / Double(total) * 0.2
        case .embedding(let done, let total):
            title = "埋め込みを計算しています（\(done)/\(total)）"
            fraction = total == 0 ? nil : 0.2 + Double(done) / Double(total) * 0.5
        case .buildingGraph:
            title = "知識グラフを作っています"
            fraction = nil
        case .saving:
            title = "保存しています"
            fraction = nil
        case .finished:
            return nil
        }
    }
}

extension RelationKind {
    /// 画面に出す名前。
    public var title: String {
        switch self {
        case .cooccurrence: "共起"
        case .hierarchy: "見出し"
        case .definition: "定義"
        case .isA: "種類"
        case .link: "リンク"
        case .contains: "包含"
        case .similar: "類似"
        }
    }
}
