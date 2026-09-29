//
//  VaultRepository.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// Vault（ノートの入ったフォルダ）のファイルを読む。書き込みはしない。
public protocol VaultRepository: Sendable {
    func loadTree() async throws(VaultError) -> VaultNode
    func readText(at path: String) async throws(VaultError) -> String
    func fileInfo(at path: String) async throws(VaultError) -> FileInfo
    /// 画像や PDF を開くための、ファイルの場所。
    func fileURL(for path: String) -> URL
    /// Vault の中で何かが変わるたびに流れる。
    func changes() -> AsyncStream<Void>
}

/// Markdown のノートの索引（SwiftData）。
public protocol NoteIndexRepository: Sendable {
    /// 索引にあるノートの、前回の目印（更新日時と大きさ）。差分の検出に使う。
    func stamps() async throws -> [String: String]
    /// 索引を作ったときの、Vault の全ファイルのパスの目印。変わっていたらリンクを解決し直す。
    func pathSignature() async throws -> String?
    func apply(_ changes: NoteIndexChanges) async throws
    func backlinks(to path: String) async throws -> [NoteSummary]
    func search(_ query: String, limit: Int) async throws -> [SearchResult]
    func tags() async throws -> [TagCount]
    func notes(taggedWith tag: String) async throws -> [NoteSummary]
    /// 索引が更新されるたびに流れる。
    func changes() -> AsyncStream<Void>
}

/// 索引へのまとめての変更。
public struct NoteIndexChanges: Sendable, Equatable {
    public var upserts: [IndexedNote]
    public var removals: [String]
    public var pathSignature: String

    public init(upserts: [IndexedNote], removals: [String], pathSignature: String) {
        self.upserts = upserts
        self.removals = removals
        self.pathSignature = pathSignature
    }
}

/// 索引に入れるノート 1 本分。
public struct IndexedNote: Sendable, Equatable {
    public let path: String
    public let title: String
    public let tags: [String]
    /// リンク先を解決した、Vault のルートからのパス。
    public let linkedPaths: [String]
    public let body: String
    public let stamp: String

    public init(path: String, title: String, tags: [String], linkedPaths: [String], body: String, stamp: String) {
        self.path = path
        self.title = title
        self.tags = tags
        self.linkedPaths = linkedPaths
        self.body = body
        self.stamp = stamp
    }
}

public struct NoteSummary: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String

    public init(path: String, title: String) {
        self.path = path
        self.title = title
    }
}

public struct SearchResult: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String
    /// 一致した箇所の前後。
    public let snippet: String

    public init(path: String, title: String, snippet: String) {
        self.path = path
        self.title = title
        self.snippet = snippet
    }
}

public struct TagCount: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}
