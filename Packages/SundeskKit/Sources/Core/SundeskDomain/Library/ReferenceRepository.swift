//
//  ReferenceRepository.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// 文献、コレクション、注釈を保存する。
public protocol ReferenceRepository: Sendable {
    func references() async throws(LibraryError) -> [Reference]
    func reference(_ id: UUID) async throws(LibraryError) -> Reference?
    /// 新しければ足し、あれば書き直す。
    func save(_ reference: Reference) async throws(LibraryError)
    /// 文献と、その注釈を消す。
    func deleteReferences(_ ids: [UUID]) async throws(LibraryError)

    func collections() async throws(LibraryError) -> [ReferenceCollection]
    func save(_ collection: ReferenceCollection) async throws(LibraryError)
    /// コレクションと、その中のコレクションを消す。文献は消さない。
    func deleteCollection(_ id: UUID) async throws(LibraryError)

    func annotations(of referenceID: UUID) async throws(LibraryError) -> [Annotation]
    func save(_ annotation: Annotation) async throws(LibraryError)
    func deleteAnnotation(_ id: UUID) async throws(LibraryError)

    /// 何かを書き換えるたびに値を流す。
    func changes() async -> AsyncStream<Void>
}
