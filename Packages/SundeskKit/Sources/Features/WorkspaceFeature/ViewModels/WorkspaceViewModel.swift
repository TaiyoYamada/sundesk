//
//  WorkspaceViewModel.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import LibraryFeature
import NotesFeature
import Observation
import SundeskDomain

/// 1 つのウインドウの状態。開いているタブ、左のナビゲータ、右のインスペクタ。
@MainActor
@Observable
public final class WorkspaceViewModel {
    public enum NavigatorMode: String, CaseIterable, Identifiable, Sendable {
        case library
        case search
        case tags

        public var id: Self { self }

        public var title: String {
            switch self {
            case .library: "ライブラリ"
            case .search: "検索"
            case .tags: "タグ"
            }
        }

        public var systemImage: String {
            switch self {
            case .library: "books.vertical"
            case .search: "magnifyingglass"
            case .tags: "tag"
            }
        }
    }

    public private(set) var tabs: [WorkspaceTab] = []
    public var selectedTabID: WorkspaceTab.ID?
    public var navigatorMode: NavigatorMode = .library
    public var isInspectorPresented = true
    /// リンク先が見つからなかったときなどに出すメッセージ。
    public var alertMessage: String?
    /// 論文（キー）の PDF で開いてほしいページ。
    public private(set) var pageRequests: [String: PDFPageRequest] = [:]

    @ObservationIgnored private let resolveLink: any ResolveLinkUseCase
    @ObservationIgnored private let makeDocument: (String) -> DocumentViewModel
    @ObservationIgnored private var documents: [String: DocumentViewModel] = [:]

    public init(resolveLink: any ResolveLinkUseCase, makeDocument: @escaping (String) -> DocumentViewModel) {
        self.resolveLink = resolveLink
        self.makeDocument = makeDocument
    }

    public var selectedTab: WorkspaceTab? {
        tabs.first { $0.id == selectedTabID }
    }

    /// 選んでいるタブのファイル。インスペクタに出す。
    public var selectedDocument: DocumentViewModel? {
        selectedTab?.documentPath.map(document(for:))
    }

    // MARK: - タブ

    /// ファイルを開く。すでに開いていれば、そのタブを選ぶ。論文や実験のフォルダの中なら、その画面で開く。
    public func open(path: String) {
        open(Self.content(for: path))
    }

    /// ファイルを開き、指定の行へ移る。
    public func open(path: String, line: Int) {
        let content = Self.content(for: path)
        open(content)
        if case .paper(let key) = content, path.lowercased().hasSuffix(".pdf") {
            // 論文の PDF なら、行はページ（知識の PDF のチャンクは、ページを行として持つ）
            pageRequests[key] = PDFPageRequest(page: line)
        } else if WorkspaceTab(content: content).documentPath == path {
            // 論文や実験の画面なら、メモ（note.md）の行へ移る
            document(for: path).reveal(line: line)
        }
    }

    /// パスを開くタブの中身。論文と実験のフォルダの中のファイルは、論文や実験の画面にする。
    ///
    /// 論文と実験はフォルダでくくれるので、キーは `最適化/peruzzo2014` のようにフォルダを含むことがある。
    /// 論文はファイルのあるフォルダ、実験は results/・figures/ などの手前までをキーにする。
    static func content(for path: String) -> WorkspaceTab.Content {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return .document(path) }
        switch parts[0] {
        case LibrarySection.papers.folder:
            return .paper(parts[1..<(parts.count - 1)].joined(separator: "/"))
        case LibrarySection.experiments.folder:
            let end = parts.firstIndex { experimentParts.contains($0) } ?? (parts.count - 1)
            guard end > 1 else { return .document(path) }
            return .experiment(parts[1..<end].joined(separator: "/"))
        default:
            return .document(path)
        }
    }

    /// 実験のフォルダの中の、決まった名前（ここより手前が実験のキー）。
    private static let experimentParts: Set<String> = ["results", "figures", "note.md", "experiment.json"]

    /// タブの題名を変える（論文や実験の題名が読めたとき）。
    public func retitle(_ content: WorkspaceTab.Content, to title: String) {
        guard !title.isEmpty, let index = tabs.firstIndex(where: { $0.content == content }),
            tabs[index].customTitle != title
        else { return }
        tabs[index].customTitle = title
    }

    public func open(tool: WorkspaceTool) {
        open(.tool(tool))
    }

    /// ~/Research のプロジェクトと実行をタブで開く。
    public func open(researchProject path: String, title: String) {
        open(.researchProject(path), title: title)
    }

    public func open(researchRun path: String, title: String) {
        open(.researchRun(path), title: title)
    }

    /// 論文、実験、比べる画面をタブで開く。
    public func open(paper key: String, title: String) {
        open(.paper(key), title: title)
    }

    public func open(experiment key: String, title: String) {
        open(.experiment(key), title: title)
    }

    public func open(comparison keys: [String]) {
        open(.comparison(keys))
    }

    public func close(_ id: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closed = tabs.remove(at: index)
        if let path = closed.documentPath, !tabs.contains(where: { $0.documentPath == path }),
            let document = documents.removeValue(forKey: path)
        {
            // 保存していない編集があれば、閉じる前に保存する
            Task { await document.flush() }
        }
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    public func closeSelectedTab() {
        if let selectedTabID { close(selectedTabID) }
    }

    /// 隣のタブへ移る。端まで行ったら反対の端へ戻る。
    public func selectAdjacentTab(offset: Int) {
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.id == selectedTabID } ?? 0
        selectedTabID = tabs[((current + offset) % tabs.count + tabs.count) % tabs.count].id
    }

    /// タブのファイルに、保存していない編集があるか。
    public func hasUnsavedChanges(_ tab: WorkspaceTab) -> Bool {
        tab.documentPath.flatMap { documents[$0] }?.hasUnsavedChanges ?? false
    }

    /// 選んでいるファイルを、自動保存を待たずに保存する（⌘S）。
    public func saveSelectedDocument() async {
        await selectedDocument?.flush()
    }

    public func document(for path: String) -> DocumentViewModel {
        if let document = documents[path] { return document }
        let document = makeDocument(path)
        documents[path] = document
        return document
    }

    // MARK: - リンク

    /// ノートの中のリンクを開く。見つからなければメッセージを出す。
    public func openLink(_ target: String, isExactPath: Bool) async {
        do {
            if let path = try await resolveLink(target, exact: isExactPath) {
                open(path: path)
            } else {
                alertMessage = "リンク先「\(target)」が見つかりません。"
            }
        } catch {
            alertMessage = "リンク先を探せませんでした: \(error)"
        }
    }

    private func open(_ content: WorkspaceTab.Content, title: String? = nil) {
        if let existing = tabs.first(where: { $0.content == content }) {
            selectedTabID = existing.id
            return
        }
        let tab = WorkspaceTab(content: content, title: title)
        // 選んでいるタブのすぐ右に開く（Safari や Xcode と同じ）
        let index = tabs.firstIndex { $0.id == selectedTabID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        selectedTabID = tab.id
    }
}
