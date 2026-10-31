//
//  ReferenceTable.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// 文献の一覧。行をダブルクリックすると、その論文の PDF を開く。PDF をドロップすると取り込む。
struct ReferenceTable: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var pendingDeletion: Set<UUID> = []

    var body: some View {
        Table(of: ReferenceRow.self, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("題名", value: \.title) { row in
                HStack(spacing: 4) {
                    Text(row.title).help(row.title)
                    if !row.hasPDF {
                        Image(systemName: "doc.badge.ellipsis")
                            .foregroundStyle(.secondary)
                            .help("PDF がありません")
                    }
                }
            }
            .width(min: 240, ideal: 520)
            TableColumn("著者", value: \.authors)
                .width(min: 80, ideal: 160)
            TableColumn("年", value: \.year) { Text($0.yearText) }
                .width(min: 40, ideal: 50)
            TableColumn("掲載先", value: \.container)
                .width(min: 80, ideal: 220)
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
            if let id = ids.first { viewModel.openReference(id) }
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
                Button("開く") { viewModel.openReference(id) }
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
