//
//  LibraryViewModel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
import Foundation
import Observation
import SundeskDomain

/// ライブラリのウインドウ（サイドバー、文献の一覧）の状態。
@MainActor
@Observable
public final class LibraryViewModel {
    public var sidebarSelection: SidebarItem? = .all
    public var query = ""
    public var selection: Set<UUID> = []
    public var sortOrder: [KeyPathComparator<ReferenceRow>]
    public var errorMessage: String?
    /// 終わった操作の結果（「書誌情報が 80 件見つかりました」など）。
    public var noticeMessage: String?
    /// 識別子を入れるシートを出しているか（メニューからも開く）。
    public var isAddingIdentifier = false
    /// PDF を選ぶパネルを出しているか。
    public var isImportingPDF = false
    /// 書き出す BibTeX。値があれば、保存のパネルを出す。
    public var exportText: String?
    /// 時間のかかる操作をしている間の説明。
    public private(set) var progressMessage: String?
    public private(set) var collectionTree: [CollectionNode] = []
    public private(set) var collectionChoices: [CollectionChoice] = []
    public private(set) var tags: [String] = []

    private var references: [Reference] = []
    private var collections: [ReferenceCollection] = []
    private let library: any ManageLibraryUseCase

    public init(library: any ManageLibraryUseCase) {
        self.library = library
        sortOrder = [KeyPathComparator(\.dateAdded, order: .reverse)]
    }

    public var rows: [ReferenceRow] {
        references.filtered(by: scope, query: query, collections: collections)
            .map(ReferenceRow.init)
            .sorted(using: sortOrder)
    }

    /// 選んでいるコレクション（コレクションを選んでいなければ nil）。
    public var selectedCollectionID: UUID? {
        if case .collection(let id) = sidebarSelection { return id }
        return nil
    }

    public var storageURL: URL {
        library.storageRoot
    }

    /// 読み込み、そのあとはライブラリの変更を見張って読み直す。
    public func start() async {
        await reload()
        for await _ in await library.changes() {
            await reload()
        }
    }

    // MARK: - 文献を足す、消す

    /// DOI、arXiv の ID、ISBN から足す。足せたら true。
    public func add(identifier text: String) async -> Bool {
        guard let identifier = ReferenceIdentifier(parsing: text) else {
            errorMessage = LibraryError.invalidIdentifier(text).message
            return false
        }
        progressMessage = "\(identifier.text) の書誌情報を取っています"
        defer { progressMessage = nil }
        do {
            let reference = try await library.add(identifier, into: selectedCollectionID)
            await select(reference.id)
            return true
        } catch {
            errorMessage = error.message
            return false
        }
    }

    public func importPDFs(_ urls: [URL]) async {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        var added: [UUID] = []
        for (index, url) in pdfs.enumerated() {
            progressMessage = "PDF を取り込んでいます（\(index + 1) / \(pdfs.count)）"
            do {
                added.append(try await library.importPDF(url, into: selectedCollectionID).id)
            } catch {
                errorMessage = "\(url.lastPathComponent): \(error.message)"
            }
        }
        progressMessage = nil
        if let last = added.last {
            await select(last)
            selection = Set(added)
        }
    }

    public func addBlank() async {
        do {
            let reference = try await library.addBlank(into: selectedCollectionID)
            await select(reference.id)
        } catch {
            errorMessage = error.message
        }
    }

    /// 書誌情報が見つかっていない文献を、PDF の題名とファイル名から探し直す。
    public func findMissingMetadata() async {
        do {
            let result = try await library.findMissingMetadata { index, count in
                await MainActor.run { self.progressMessage = "書誌情報を探しています（\(index) / \(count)）" }
            }
            noticeMessage =
                result.total == 0
                ? "書誌情報が見つかっていない文献はありません"
                : "\(result.total) 件のうち \(result.found) 件の書誌情報が見つかりました。見つからなかった文献は、題名だけ PDF から拾い直しました"
        } catch {
            errorMessage = error.message
        }
        progressMessage = nil
    }

    /// PDF を、Mac の既定のアプリ（プレビューなど）で開く。
    public func openPDFExternally(_ id: UUID) async {
        guard let reference = try? await library.reference(id), let url = library.pdfURL(of: reference) else { return }
        NSWorkspace.shared.open(url)
    }

    public func delete(_ ids: Set<UUID>) async {
        do {
            try await library.delete(Array(ids))
            selection.subtract(ids)
        } catch {
            errorMessage = error.message
        }
    }

    // MARK: - コレクション

    public func createCollection(named name: String, parentID: UUID?) async {
        do {
            let collection = try await library.createCollection(named: name, parentID: parentID)
            await reload()
            sidebarSelection = .collection(collection.id)
        } catch {
            errorMessage = error.message
        }
    }

    public func collectionName(_ id: UUID) -> String {
        collections.first { $0.id == id }?.name ?? ""
    }

    public func renameCollection(_ id: UUID, to name: String) async {
        guard var collection = collections.first(where: { $0.id == id }) else { return }
        collection.name = name
        do {
            try await library.save(collection)
        } catch {
            errorMessage = error.message
        }
    }

    public func deleteCollection(_ id: UUID) async {
        if selectedCollectionID.map(collections.descendantIDs(of: id).contains) == true { sidebarSelection = .all }
        do {
            try await library.deleteCollection(id)
        } catch {
            errorMessage = error.message
        }
    }

    public func add(_ ids: Set<UUID>, toCollection collectionID: UUID) async {
        do {
            try await library.add(Array(ids), to: collectionID)
        } catch {
            errorMessage = error.message
        }
    }

    /// 選んでいるコレクションから外す（文献は消さない）。
    public func removeFromSelectedCollection(_ ids: Set<UUID>) async {
        guard let collectionID = selectedCollectionID else { return }
        do {
            try await library.remove(Array(ids), from: collectionID)
        } catch {
            errorMessage = error.message
        }
    }

    // MARK: - 書き出し

    public func bibTeX(for ids: Set<UUID>) async -> String {
        do {
            return try await library.bibTeX(for: Array(ids))
        } catch {
            errorMessage = error.message
            return ""
        }
    }

    public func copyBibTeX(for ids: Set<UUID>) async {
        let text = await bibTeX(for: ids)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 今の一覧に出ている文献すべてを書き出す（保存のパネルを出す）。
    public func exportVisibleRows() async {
        exportText = await bibTeX(for: Set(rows.map(\.id)))
    }

    /// 書き出すファイルの既定の名前。
    public var exportFileName: String {
        let name =
            switch sidebarSelection {
            case .collection(let id): collectionName(id)
            case .tag(let tag): tag
            case .all, .unfiled, nil: "library"
            }
        return "\(name).bib"
    }

    // MARK: - 読み込み

    private var scope: LibraryScope {
        switch sidebarSelection {
        case .all, nil: .all
        case .unfiled: .unfiled
        case .collection(let id): .collection(id)
        case .tag(let tag): .tag(tag)
        }
    }

    private func reload() async {
        do {
            references = try await library.references()
            collections = try await library.collections()
        } catch {
            errorMessage = error.message
            return
        }
        tags = references.allTags
        collectionTree = tree(parentID: nil)
        collectionChoices = choices(parentID: nil, prefix: "")
        selection.formIntersection(references.map(\.id))
    }

    private func select(_ id: UUID) async {
        await reload()
        // 足した文献が今の一覧に出ないときは、検索をやめて、すべての文献を見せる
        if !rows.contains(where: { $0.id == id }) {
            query = ""
            sidebarSelection = .all
        }
        selection = [id]
    }

    private func tree(parentID: UUID?) -> [CollectionNode] {
        collections.filter { $0.parentID == parentID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { collection in
                let children = tree(parentID: collection.id)
                return CollectionNode(
                    id: collection.id, name: collection.name, children: children.isEmpty ? nil : children)
            }
    }

    private func choices(parentID: UUID?, prefix: String) -> [CollectionChoice] {
        collections.filter { $0.parentID == parentID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .flatMap { collection in
                let path = prefix + collection.name
                return [CollectionChoice(id: collection.id, path: path)]
                    + choices(parentID: collection.id, prefix: path + " / ")
            }
    }
}
