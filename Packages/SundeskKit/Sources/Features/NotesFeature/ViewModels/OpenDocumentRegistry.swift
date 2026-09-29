//
//  OpenDocumentRegistry.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

/// 開いているファイル（すべてのウインドウ）。アプリを終了する前に、保存していない編集を保存する。
@MainActor
public final class OpenDocumentRegistry {
    private final class WeakDocument {
        weak var document: DocumentViewModel?

        init(_ document: DocumentViewModel) {
            self.document = document
        }
    }

    private var documents: [WeakDocument] = []

    public init() {}

    public func register(_ document: DocumentViewModel) {
        documents.removeAll { $0.document == nil }
        documents.append(WeakDocument(document))
    }

    /// 保存していない編集をすべて保存する。
    public func saveAll() async {
        for document in documents.compactMap(\.document) {
            await document.flush()
        }
    }
}
