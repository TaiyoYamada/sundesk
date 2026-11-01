//
//  AddIdentifierSheet.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// DOI、arXiv の ID、ISBN を入れて文献を足すシート。
struct AddIdentifierSheet: View {
    let onAdd: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("識別子で文献を足す").font(.headline)
            TextField("DOI、arXiv の ID、ISBN", text: $text, prompt: Text("10.1038/ncomms5213、2101.00001、URL も可"))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 420)
                .onSubmit(add)
            Text("arXiv の論文は PDF も取ってきます。").font(.callout).foregroundStyle(.secondary)
            HStack {
                if isAdding { ProgressView().controlSize(.small) }
                Spacer()
                Button("キャンセル", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("足す", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
        }
        .padding(20)
    }

    private func add() {
        isAdding = true
        Task {
            if await onAdd(text) { dismiss() }
            isAdding = false
        }
    }
}
