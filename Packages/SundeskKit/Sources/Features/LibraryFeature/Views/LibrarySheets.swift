//
//  LibrarySheets.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI

// 論文、ノート、実験を足すときのシート。

struct AddPaperSheet: View {
    let viewModel: LibraryViewModel
    let done: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""
    @State private var downloadsPDF = true
    @State private var isAdding = false

    var body: some View {
        Form {
            TextField("arXiv の ID か DOI（URL でもよい）", text: $identifier)
                .onSubmit { add() }
            Toggle("arXiv の PDF も取ってくる", isOn: $downloadsPDF)
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.orange).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAdding ? "取っています…" : "足す") { add() }.disabled(identifier.isEmpty || isAdding)
            }
        }
    }

    private func add() {
        isAdding = true
        Task {
            let key = await viewModel.addPaper(identifier: identifier, downloadsPDF: downloadsPDF)
            isAdding = false
            if key != nil {
                dismiss()
                done(key)
            }
        }
    }
}

struct NewNoteSheet: View {
    let viewModel: LibraryViewModel
    let done: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())

    var body: some View {
        Form {
            TextField("名前", text: $name)
            Text("研究ログなら日付、アイデアや議事なら内容の分かる名前にします。").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("作る") {
                    Task {
                        let path = await viewModel.createNote(named: name)
                        dismiss()
                        done(path)
                    }
                }
                .disabled(name.isEmpty)
            }
        }
    }
}

struct NewExperimentSheet: View {
    let viewModel: LibraryViewModel
    let done: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var algorithm = "GA"
    @State private var problem = ""

    var body: some View {
        Form {
            TextField("名前", text: $title)
            Picker("アルゴリズム", selection: $algorithm) {
                ForEach(ExperimentViewModel.algorithms, id: \.self) { Text($0).tag($0) }
            }
            TextField("問題とインスタンス", text: $problem)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("作る") {
                    Task {
                        let key = await viewModel.createExperiment(title: title, algorithm: algorithm, problem: problem)
                        dismiss()
                        done(key)
                    }
                }
                .disabled(title.isEmpty)
            }
        }
    }
}
