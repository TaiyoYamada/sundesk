//
//  NoteEditor.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
import SundeskEditorUI
import SwiftUI

/// 文献のメモ（Markdown のライブプレビュー）。
struct NoteEditor: View {
    let viewModel: ReferenceDetailViewModel
    @State private var session = TextEditorSession()

    var body: some View {
        TextEditorView(
            session: session,
            text: Binding(get: { viewModel.draft?.note ?? "" }, set: { viewModel.draft?.note = $0 }),
            syntax: .markdown(livePreview: true, notePath: ""),
            scrollToLine: .constant(nil),
            onOpen: open)
    }

    private func open(_ link: DocumentLink) {
        if case .external(let url) = link { NSWorkspace.shared.open(url) }
    }
}
