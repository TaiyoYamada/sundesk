//
//  LibraryAccess.swift
//  SundeskCLI
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskData
import SundeskDomain

/// CLI と MCP サーバーが使う、ライブラリの操作。文献は引用キーで、コレクションは名前（「親/子」）で指す。
struct LibraryAccess {
    let library: any ManageLibraryUseCase

    /// アプリと同じライブラリを開く。
    static func open() throws -> LibraryAccess {
        let directory: URL
        // テストで本物のライブラリを汚さないよう、環境変数で差し替えられる
        if let path = ProcessInfo.processInfo.environment["SUNDESK_LIBRARY"] {
            directory = URL(filePath: path, directoryHint: .isDirectory)
        } else {
            directory = try AppDataDirectory.url("Library")
        }
        let repository = try SwiftDataReferenceRepository.open(at: directory.appending(path: "library.store"))
        let attachments = FileAttachmentStore(root: directory.appending(path: "Storage", directoryHint: .isDirectory))
        let library = LibraryInteractor(
            repository: repository, attachments: attachments, bibliography: OnlineBibliography(), pdfs: PDFKitReader())
        return LibraryAccess(library: library)
    }

    /// 検索の語で探す。新しく足した順に返す。
    func search(_ query: String, collection: String?, tag: String?, limit: Int?) async throws -> [ReferenceItem] {
        let collections = try await library.collections()
        let scope: LibraryScope =
            if let collection {
                .collection(try find(collection, in: collections).id)
            } else if let tag {
                .tag(tag)
            } else {
                .all
            }
        let found = try await library.references()
            .filtered(by: scope, query: query, collections: collections)
            .sorted { $0.dateAdded > $1.dateAdded }
        return found.prefix(limit ?? found.count).map { item($0, collections: collections, detailed: false) }
    }

    /// 要旨、メモ、要約まで含めて返す。
    func reference(key: String) async throws -> ReferenceItem {
        let reference = try await find(key: key)
        return item(reference, collections: try await library.collections(), detailed: true)
    }

    func collections() async throws -> [CollectionItem] {
        let collections = try await library.collections()
        let references = try await library.references()
        return collections.map { collection in
            let count = references.filtered(by: .collection(collection.id), query: "", collections: collections).count
            return CollectionItem(path: collections.path(of: collection.id), count: count)
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func bibTeX(keys: [String]) async throws -> String {
        var ids: [UUID] = []
        for key in keys { ids.append(try await find(key: key).id) }
        return try await library.bibTeX(for: ids)
    }

    /// DOI、arXiv の ID、ISBN、または PDF のパスから足す。同じ文献がすでにあれば、それを返す。
    func add(_ text: String, collection: String?) async throws -> ReferenceItem {
        let collections = try await library.collections()
        let collectionID = try collection.map { try find($0, in: collections).id }
        let file = URL(filePath: (text as NSString).expandingTildeInPath)
        let reference: Reference
        if file.pathExtension.lowercased() == "pdf", FileManager.default.fileExists(atPath: file.path) {
            reference = try await library.importPDF(file, into: collectionID)
        } else if let identifier = ReferenceIdentifier(parsing: text) {
            reference = try await library.add(identifier, into: collectionID)
        } else {
            throw LibraryError.invalidIdentifier(text)
        }
        return item(reference, collections: collections, detailed: false)
    }

    /// 文献をコレクションに入れる。入っていたコレクションからは外さない。
    func collect(keys: [String], into collection: String) async throws -> [ReferenceItem] {
        let collections = try await library.collections()
        let target = try find(collection, in: collections)
        var references: [Reference] = []
        for key in keys { references.append(try await find(key: key)) }
        try await library.add(references.map(\.id), to: target.id)
        var collected: [ReferenceItem] = []
        for reference in references {
            guard let updated = try await library.reference(reference.id) else { continue }
            collected.append(item(updated, collections: collections, detailed: false))
        }
        return collected
    }

    private func find(key: String) async throws -> Reference {
        guard let reference = try await library.references().first(where: { $0.citationKey == key }) else {
            throw CommandError.unknownReference(key)
        }
        return reference
    }

    private func find(_ name: String, in collections: [ReferenceCollection]) throws -> ReferenceCollection {
        let matches = collections.matching(name)
        switch matches.count {
        case 0: throw CommandError.unknownCollection(name)
        case 1: return matches[0]
        default: throw CommandError.ambiguousCollection(name, matches.map { collections.path(of: $0.id) })
        }
    }

    private func item(_ reference: Reference, collections: [ReferenceCollection], detailed: Bool) -> ReferenceItem {
        ReferenceItem(
            reference, collections: collections, pdf: library.pdfURL(of: reference), detailed: detailed)
    }
}
