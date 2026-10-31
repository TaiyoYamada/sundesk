//
//  ManageLibraryUseCase.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// ライブラリの操作（画面が使うもの一式）。
public protocol ManageLibraryUseCase: Sendable {
    func references() async throws(LibraryError) -> [Reference]
    func reference(_ id: UUID) async throws(LibraryError) -> Reference?
    func collections() async throws(LibraryError) -> [ReferenceCollection]
    /// ライブラリが書き換わるたびに値を流す。
    func changes() async -> AsyncStream<Void>

    /// 識別子から文献を足す。すでにあれば、それを返す。arXiv なら PDF も取ってくる。
    /// - Parameter collectionID: 足した文献を入れるコレクション。
    func add(_ identifier: ReferenceIdentifier, into collectionID: UUID?) async throws(LibraryError) -> Reference
    /// PDF から文献を足す。PDF の DOI や arXiv の ID、題名、ファイル名から書誌情報を探す。
    func importPDF(_ url: URL, into collectionID: UUID?) async throws(LibraryError) -> Reference
    /// 書誌情報を手で入れる、空の文献を足す。
    func addBlank(into collectionID: UUID?) async throws(LibraryError) -> Reference
    func attachPDF(_ url: URL, to referenceID: UUID) async throws(LibraryError)
    func save(_ reference: Reference) async throws(LibraryError)
    /// DOI、arXiv の ID、ISBN から書誌情報を引き直す。どれもなければ、PDF の題名とファイル名から探す。
    func refreshMetadata(of referenceID: UUID) async throws(LibraryError)
    /// 書誌情報が見つかっていない文献（DOI、arXiv の ID、ISBN のどれもない、PDF のある文献）を探し直す。
    /// 見つからなかった文献は、題名だけを PDF から拾い直す。
    /// - Parameter progress: 何件目か（1 始まり）と、全部の件数。
    /// - Returns: 書誌情報が見つかった件数と、探した件数。
    func findMissingMetadata(
        progress: @Sendable (Int, Int) async -> Void
    ) async throws(LibraryError) -> (found: Int, total: Int)
    /// 文献と、その PDF と注釈を消す。
    func delete(_ ids: [UUID]) async throws(LibraryError)

    func createCollection(named name: String, parentID: UUID?) async throws(LibraryError) -> ReferenceCollection
    func save(_ collection: ReferenceCollection) async throws(LibraryError)
    /// コレクションを別のコレクションの中へ移す（nil なら一番上へ）。自分の中へは移さない。
    func moveCollection(_ id: UUID, into parentID: UUID?) async throws(LibraryError)
    func deleteCollection(_ id: UUID) async throws(LibraryError)
    func add(_ ids: [UUID], to collectionID: UUID) async throws(LibraryError)
    func remove(_ ids: [UUID], from collectionID: UUID) async throws(LibraryError)

    func annotations(of referenceID: UUID) async throws(LibraryError) -> [Annotation]
    func save(_ annotation: Annotation) async throws(LibraryError)
    func deleteAnnotation(_ id: UUID) async throws(LibraryError)

    func bibTeX(for ids: [UUID]) async throws(LibraryError) -> String
    func pdfURL(of reference: Reference) -> URL?
    /// PDF を置いているフォルダ。
    var storageRoot: URL { get }
}
