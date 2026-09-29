//
//  WorkspaceViewModel.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 1 つのウインドウの状態。開いているタブ、左のナビゲータ、右のインスペクタ。
@MainActor
@Observable
public final class WorkspaceViewModel {
    public enum NavigatorMode: String, CaseIterable, Identifiable, Sendable {
        case files
        case search
        case tags

        public var id: Self { self }

        public var title: String {
            switch self {
            case .files: "ファイル"
            case .search: "検索"
            case .tags: "タグ"
            }
        }

        public var systemImage: String {
            switch self {
            case .files: "folder"
            case .search: "magnifyingglass"
            case .tags: "tag"
            }
        }
    }

    public private(set) var tabs: [WorkspaceTab] = []
    public var selectedTabID: WorkspaceTab.ID?
    public var navigatorMode: NavigatorMode = .files
    public var isInspectorPresented = true
    /// リンク先が見つからなかったときなどに出すメッセージ。
    public var alertMessage: String?

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

    /// ファイルを開く。すでに開いていれば、そのタブを選ぶ。
    public func open(path: String) {
        open(.document(path))
    }

    public func open(feature: WorkspaceFeature) {
        open(.feature(feature))
    }

    public func close(_ id: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closed = tabs.remove(at: index)
        if let path = closed.documentPath, !tabs.contains(where: { $0.documentPath == path }) {
            documents[path] = nil
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

    private func open(_ content: WorkspaceTab.Content) {
        if let existing = tabs.first(where: { $0.content == content }) {
            selectedTabID = existing.id
            return
        }
        let tab = WorkspaceTab(content: content)
        // 選んでいるタブのすぐ右に開く（Safari や Xcode と同じ）
        let index = tabs.firstIndex { $0.id == selectedTabID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        selectedTabID = tab.id
    }
}
