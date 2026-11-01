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
    public var sidebarSelection: SidebarItem? = .all {
        didSet { revealSelection() }
    }
    /// サイドバーで開いている行。
    public var expandedItems: Set<SidebarItem> = []
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
    /// コレクションの木（中のコレクションと論文を含む）。
    public private(set) var collectionTree: [SidebarNode] = []
    /// 「未整理」の行（どのコレクションにも入っていない論文を含む）。
    public private(set) var unfiledNode = SidebarNode(id: .unfiled, name: "未整理", kind: .unfiled, children: nil)
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

    /// 選んでいるコレクション。論文を選んでいるときは、その行のあるコレクション。
    public var selectedCollectionID: UUID? {
        switch sidebarSelection {
        case .collection(let id): id
        case .reference(_, let collectionID): collectionID
        case .all, .unfiled, .tag, nil: nil
        }
    }

    /// サイドバーで選んでいる論文（PDF を出す）。フォルダを選んでいれば nil（一覧を出す）。
    public var selectedReferenceID: UUID? {
        if case .reference(let id, _) = sidebarSelection { return id }
        return nil
    }

    /// 一覧から論文を開く。今見ているフォルダの中にその論文の行があれば、その行を選ぶ。
    public func openReference(_ id: UUID) {
        guard let reference = references.first(where: { $0.id == id }) else { return }
        let inFolder: Set<UUID> =
            switch sidebarSelection {
            case .collection(let folder): collections.descendantIDs(of: folder)
            case .all, .unfiled, .tag, .reference, nil: []
            }
        let parent =
            reference.collectionIDs.first(where: inFolder.contains)
            ?? collectionChoices.first { reference.collectionIDs.contains($0.id) }?.id
        sidebarSelection = .reference(id, parent: parent)
    }

    /// 論文を見ているときの、その論文の行の親のフォルダ（検索を始めたときに一覧へ戻るため）。
    public func returnToFolder() {
        guard case .reference(_, let parent) = sidebarSelection else { return }
        sidebarSelection = parent.map(SidebarItem.collection) ?? .unfiled
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
                : "\(result.total) 件のうち \(result.found) 件の書誌情報が見つかりました。見つからなかった文献は、題名、著者、年を PDF とファイル名から埋め直しました"
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
        if let id = selectedReferenceID, ids.contains(id) { returnToFolder() }
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

    /// コレクションを別のコレクションの中へ移す（nil なら一番上へ）。
    public func moveCollection(_ id: UUID, into parentID: UUID?) async {
        guard id != parentID else { return }
        do {
            try await library.moveCollection(id, into: parentID)
        } catch {
            errorMessage = error.message
        }
    }

    /// 一番上の階層にあるか。
    public func isTopLevelCollection(_ id: UUID) -> Bool {
        collections.first { $0.id == id }?.parentID == nil
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
        await remove(ids, fromCollection: collectionID)
    }

    /// コレクションから外す（文献は消さない）。外した論文の行を見ていたら、そのコレクションの一覧に戻る。
    public func remove(_ ids: Set<UUID>, fromCollection collectionID: UUID) async {
        if case .reference(let id, collectionID) = sidebarSelection, ids.contains(id) {
            sidebarSelection = .collection(collectionID)
        }
        do {
            try await library.remove(Array(ids), from: collectionID)
        } catch {
            errorMessage = error.message
        }
    }

    // MARK: - 読み込み

    private var scope: LibraryScope {
        switch sidebarSelection {
        case .all, nil: .all
        case .unfiled: .unfiled
        case .collection(let id): .collection(id)
        case .tag(let tag): .tag(tag)
        case .reference: .all
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
        let tree = SidebarTree(references: references, collections: collections)
        collectionTree = tree.collectionNodes(parentID: nil)
        unfiledNode = tree.unfiledNode
        collectionChoices = tree.choices(parentID: nil, prefix: "")
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

    /// 選んだ論文の行が見えるように、親のコレクションを開く。
    private func revealSelection() {
        guard case .reference(_, let parent) = sidebarSelection else { return }
        guard let parent else {
            expandedItems.insert(.unfiled)
            return
        }
        var current: UUID? = parent
        while let id = current {
            expandedItems.insert(.collection(id))
            current = collections.first { $0.id == id }?.parentID
        }
    }
}

// MARK: - 書き出し

extension LibraryViewModel {

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
            case .all, .unfiled, .reference, nil: "library"
            }
        return "\(name).bib"
    }
}
