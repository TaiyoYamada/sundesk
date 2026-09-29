//
//  DocumentViewModel.swift
//  SundeskPresentation
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 開いた 1 つのファイル。表示とソースの切り替え、インスペクタの情報を持つ。
@MainActor
@Observable
public final class DocumentViewModel {
    public enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
        case rendered
        case source

        public var id: Self { self }

        public var title: String {
            switch self {
            case .rendered: "表示"
            case .source: "ソース"
            }
        }

        public var systemImage: String {
            switch self {
            case .rendered: "doc.richtext"
            case .source: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    public let path: String
    public let kind: FileKind
    public private(set) var document: Document?
    public private(set) var errorMessage: String?
    public private(set) var backlinks: [NoteSummary] = []
    public var displayMode: DisplayMode

    @ObservationIgnored private let openDocument: any OpenDocumentUseCase
    @ObservationIgnored private let findBacklinks: any FindBacklinksUseCase

    public init(path: String, openDocument: any OpenDocumentUseCase, findBacklinks: any FindBacklinksUseCase) {
        self.path = path
        self.kind = FileKind(fileName: path.split(separator: "/").last.map(String.init) ?? path)
        self.displayMode = kind.hasRenderedView ? .rendered : .source
        self.openDocument = openDocument
        self.findBacklinks = findBacklinks
    }

    public var title: String {
        document?.title ?? path.split(separator: "/").last.map(String.init) ?? path
    }

    /// 表示とソースの両方を持つファイル（Markdown と HTML）だけ切り替えられる。
    public var canToggleDisplayMode: Bool {
        kind.hasRenderedView && kind.hasSourceView
    }

    public func toggleDisplayMode() {
        guard canToggleDisplayMode else { return }
        displayMode = displayMode == .rendered ? .source : .rendered
    }

    public var properties: [NoteProperty] {
        if case .markdown(_, let analysis) = document?.content { analysis.properties } else { [] }
    }

    public var tags: [String] {
        if case .markdown(_, let analysis) = document?.content { analysis.tags } else { [] }
    }

    /// ファイルを読み直す。Vault が変わったときにも呼ぶ。
    public func load() async {
        do {
            let loaded = try await openDocument(path: path)
            if loaded != document { document = loaded }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
        await loadBacklinks()
    }

    public func loadBacklinks() async {
        guard kind == .markdown || kind == .html else { return }
        backlinks = (try? await findBacklinks(to: path)) ?? []
    }

    static func message(for error: VaultError) -> String {
        switch error {
        case .fileNotFound: "ファイルが見つかりません。移動したか、削除された可能性があります。"
        case .vaultNotFound(let path): "Vault のフォルダが見つかりません（\(path)）。"
        case .unreadable(_, let reason): "ファイルを読めませんでした: \(reason)"
        }
    }
}
