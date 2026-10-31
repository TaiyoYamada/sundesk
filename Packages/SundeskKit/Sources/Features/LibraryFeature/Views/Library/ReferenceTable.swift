//
//  ReferenceTable.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// 文献の一覧。PDF をドロップすると取り込む。
struct ReferenceTable: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var pendingDeletion: Set<UUID> = []

    var body: some View {
        Table(of: ReferenceRow.self, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("題名", value: \.title) { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.hasPDF ? "doc.richtext" : "doc")
                        .foregroundStyle(row.hasPDF ? .primary : .tertiary)
                }
            }
            .width(min: 200, ideal: 360)
            TableColumn("著者", value: \.authors)
                .width(min: 80, ideal: 140)
            TableColumn("年", value: \.year) { Text($0.yearText) }
                .width(min: 40, ideal: 50)
            TableColumn("掲載先", value: \.container)
                .width(min: 80, ideal: 160)
            TableColumn("追加日", value: \.dateAdded) { Text($0.dateAdded, format: .dateTime.year().month().day()) }
                .width(min: 70, ideal: 90)
            TableColumn("状態") { row in
                Image(systemName: row.status.systemImage).help(row.status.title)
            }
            .width(36)
        } rows: {
            ForEach(viewModel.rows) { row in
                TableRow(row).draggable(row.id.uuidString)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            // 一覧で選べば右に PDF が出るので、ダブルクリックは Mac の既定のアプリ（プレビューなど）で開く
            if let id = ids.first { Task { await viewModel.openPDFExternally(id) } }
        }
        .onDeleteCommand { pendingDeletion = viewModel.selection }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await viewModel.importPDFs(urls) }
            return true
        }
        .overlay {
            if viewModel.rows.isEmpty {
                ContentUnavailableView(
                    "文献がありません", systemImage: "books.vertical",
                    description: Text("DOI や arXiv の ID から足すか、PDF をここにドロップしてください。"))
            }
        }
        .confirmationDialog(
            "\(pendingDeletion.count) 件の文献を削除しますか？", isPresented: isConfirmingDeletion
        ) {
            Button("削除", role: .destructive) {
                let ids = pendingDeletion
                Task { await viewModel.delete(ids) }
            }
        } message: {
            Text("添付した PDF、注釈、メモも消えます。")
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            if ids.count == 1, let id = ids.first {
                Button("既定のアプリで開く") { Task { await viewModel.openPDFExternally(id) } }
                Divider()
            }
            Menu("コレクションに追加") {
                ForEach(viewModel.collectionChoices) { choice in
                    Button(choice.path) { Task { await viewModel.add(ids, toCollection: choice.id) } }
                }
            }
            .disabled(viewModel.collectionChoices.isEmpty)
            if viewModel.selectedCollectionID != nil {
                Button("このコレクションから外す") { Task { await viewModel.removeFromSelectedCollection(ids) } }
            }
            Divider()
            Button("BibTeX をコピー") { Task { await viewModel.copyBibTeX(for: ids) } }
            Divider()
            Button("削除…", role: .destructive) { pendingDeletion = ids }
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
    }
}
