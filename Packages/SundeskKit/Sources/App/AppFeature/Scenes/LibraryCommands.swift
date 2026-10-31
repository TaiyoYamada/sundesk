//
//  LibraryCommands.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import LibraryFeature
import SwiftUI

/// 「ファイル」メニューの、文献を足す操作と BibTeX の書き出し。ライブラリのウインドウが手前にあるときに効く。
struct LibraryCommands: Commands {
    @FocusedValue(LibraryViewModel.self) private var library

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("識別子で文献を足す…") { library?.isAddingIdentifier = true }
                .keyboardShortcut("n")
                .disabled(library == nil)
            Button("PDF を取り込む…") { library?.isImportingPDF = true }
                .keyboardShortcut("o")
                .disabled(library == nil)
            Button("文献を手で入れる") {
                let library = library
                Task { await library?.addBlank() }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(library == nil)
        }

        CommandGroup(replacing: .importExport) {
            Button("選んだ文献の BibTeX をコピー") {
                guard let library else { return }
                Task { await library.copyBibTeX(for: library.selection) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(library?.selection.isEmpty != false)
            Button("一覧の文献を BibTeX に書き出す…") {
                let library = library
                Task { await library?.exportVisibleRows() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(library?.rows.isEmpty != false)
        }
    }
}
