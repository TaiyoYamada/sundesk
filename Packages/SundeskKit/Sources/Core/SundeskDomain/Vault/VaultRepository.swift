//
//  VaultRepository.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

/// Vault（ノートの入ったフォルダ）のファイルを読み書きする。
public protocol VaultRepository: Sendable {
    func loadTree() async throws(VaultError) -> VaultNode
    func readText(at path: String) async throws(VaultError) -> String
    /// テキストを書き込む（まるごと置き換える）。
    func writeText(_ text: String, to path: String) async throws(VaultError)
    func fileInfo(at path: String) async throws(VaultError) -> FileInfo
    /// Vault のフォルダの場所。
    func rootURL() -> URL
    /// 画像や PDF を開くための、ファイルの場所。
    func fileURL(for path: String) -> URL
    /// Vault の中で何かが変わるたびに流れる。
    func changes() -> AsyncStream<Void>
    /// 読むだけのファイルか（つないだ外のフォルダの中など）。
    func isReadOnly(_ path: String) -> Bool

    /// フォルダを作る。作ったパスを返す（名前が重なれば番号を付ける）。
    func createFolder(named name: String, in folder: String) async throws(VaultError) -> String
    /// ファイルやフォルダを、別のフォルダへ移す。移した先のパスを返す。
    func move(_ path: String, into folder: String) async throws(VaultError) -> String
    /// 名前を変える。変えたあとのパスを返す。
    func rename(_ path: String, to name: String) async throws(VaultError) -> String
    /// ゴミ箱に入れる。
    func moveToTrash(_ path: String) async throws(VaultError)
}

extension VaultRepository {
    public func isReadOnly(_ path: String) -> Bool { false }
    public func createFolder(named name: String, in folder: String) async throws(VaultError) -> String {
        throw .unwritable(path: folder, reason: "この Vault では作れません")
    }
    public func move(_ path: String, into folder: String) async throws(VaultError) -> String {
        throw .unwritable(path: path, reason: "この Vault では移せません")
    }
    public func rename(_ path: String, to name: String) async throws(VaultError) -> String {
        throw .unwritable(path: path, reason: "この Vault では名前を変えられません")
    }
    public func moveToTrash(_ path: String) async throws(VaultError) {
        throw .unwritable(path: path, reason: "この Vault では消せません")
    }
}

/// Markdown のノートの索引（SwiftData）。
public protocol NoteIndexRepository: Sendable {
    /// 索引にあるノートの、前回の目印（更新日時と大きさ）。差分の検出に使う。
    func stamps() async throws(NoteIndexError) -> [String: String]
    /// 索引を作ったときの、Vault の全ファイルのパスの目印。変わっていたらリンクを解決し直す。
    func pathSignature() async throws(NoteIndexError) -> String?
    func apply(_ changes: NoteIndexChanges) async throws(NoteIndexError)
    func backlinks(to path: String) async throws(NoteIndexError) -> [NoteSummary]
    func search(_ query: String, limit: Int) async throws(NoteIndexError) -> [SearchResult]
    func tags() async throws(NoteIndexError) -> [TagCount]
    func notes(taggedWith tag: String) async throws(NoteIndexError) -> [NoteSummary]
    /// 索引が更新されるたびに流れる。
    func changes() -> AsyncStream<Void>
}

public enum NoteIndexError: Error, Sendable, Equatable {
    /// 保存先（SwiftData）の読み書きに失敗した。
    case storage(String)
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
