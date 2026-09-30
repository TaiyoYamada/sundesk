//
//  ResearchScreens.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import SundeskDesignSystem
import SwiftUI

/// ~/Research のプロジェクトのタブ。左に README（と docs/）、右に見つけた実行の一覧。
public struct ResearchProjectScreen<Document: View>: View {
    private let viewModel: ResearchProjectViewModel
    private let openRun: (_ path: String, _ title: String) -> Void
    private let document: (String) -> Document
    @State private var shownDocument: String?

    /// - Parameters:
    ///   - openRun: 実行をタブで開く。
    ///   - document: Markdown を読むだけで見せる（README など）。
    public init(
        viewModel: ResearchProjectViewModel, openRun: @escaping (_ path: String, _ title: String) -> Void,
        @ViewBuilder document: @escaping (String) -> Document
    ) {
        self.viewModel = viewModel
        self.openRun = openRun
        self.document = document
    }

    public var body: some View {
        SplitPane(.horizontal, fraction: 0.62, minFirst: 360, minSecond: 260) {
            if let path = shownDocument ?? viewModel.readmePath {
                document(path).id(path)
            } else {
                ContentUnavailableView("README はありません", systemImage: "doc.text")
            }
        } second: {
            List {
                if let summary = viewModel.summary {
                    Section("概要") { Text(summary).font(.callout).textSelection(.enabled) }
                }
                if viewModel.documents.count > 1 {
                    Section("文書") {
                        ForEach(viewModel.documents, id: \.self) { path in
                            Button {
                                shownDocument = path
                            } label: {
                                Label(Self.name(of: path), systemImage: "doc.text")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(viewModel.groups) { group in
                    Section("\(group.folder)（\(group.runs.count)）") {
                        ForEach(group.runs) { run in
                            Button {
                                openRun(run.path, run.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(run.name).lineLimit(1)
                                    Text([run.date, run.detail].filter { !$0.isEmpty }.joined(separator: "・"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.isLoaded, viewModel.groups.isEmpty {
                    ContentUnavailableView(
                        "実行は見つかりません", systemImage: "tray",
                        description: Text("config.json か CSV のあるフォルダを、1 回の実行として拾います。"))
                }
            }
        }
        .task { await viewModel.load() }
        .overlay {
            if let error = viewModel.errorMessage {
                ContentUnavailableView("開けませんでした", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
    }

    private static func name(of path: String) -> String {
        path.split(separator: "/").suffix(2).joined(separator: "/")
    }
}

/// ~/Research の 1 回の実行のタブ。設定、図、表の先頭、所見（comments.md など）を見る。読むだけ。
public struct ResearchRunScreen<Document: View>: View {
    @Bindable private var viewModel: ResearchRunViewModel
    private let openPath: (String) -> Void
    private let document: (String) -> Document
    @State private var showsAllParameters = false

    /// - Parameters:
    ///   - openPath: 図や表のファイルをタブで開く。
    ///   - document: 所見の Markdown を読むだけで見せる。
    public init(
        viewModel: ResearchRunViewModel, openPath: @escaping (String) -> Void,
        @ViewBuilder document: @escaping (String) -> Document
    ) {
        self.viewModel = viewModel
        self.openPath = openPath
        self.document = document
    }

    public var body: some View {
        Group {
            if let note = viewModel.notes.first {
                SplitPane(.vertical, fraction: 0.62, minFirst: 240, minSecond: 160) {
                    details
                } second: {
                    document(note).id(note)
                }
            } else {
                details
            }
        }
        .task { await viewModel.load() }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.orange)
                }
                if !viewModel.parameters.isEmpty { parameters }
                if !viewModel.tables.isEmpty { tables }
                if !viewModel.figures.isEmpty { figures }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.projectTitle).font(.callout).foregroundStyle(.secondary)
            Text(viewModel.name).font(.title2.weight(.semibold)).textSelection(.enabled)
            HStack(spacing: 12) {
                if !viewModel.date.isEmpty { Label(viewModel.date, systemImage: "calendar") }
                Label(viewModel.relativePath, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Finder で表示", systemImage: "folder") { NSWorkspace.shared.open(viewModel.folderURL) }
                    .labelStyle(.iconOnly)
                    .help("Finder で表示")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Label("~/Research のファイルを、その場で読んでいます（書き換えません）", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var parameters: some View {
        InspectorSection("設定（config.json）") {
            let rows = showsAllParameters ? viewModel.parameters : Array(viewModel.parameters.prefix(16))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.key).foregroundStyle(.secondary)
                        Text(row.value).textSelection(.enabled).lineLimit(3)
                    }
                }
            }
            .font(.callout)
            if viewModel.parameters.count > 16 {
                Button(showsAllParameters ? "閉じる" : "すべて見る（\(viewModel.parameters.count) 項目）") {
                    showsAllParameters.toggle()
                }
                .buttonStyle(.link)
            }
        }
    }

    private var tables: some View {
        InspectorSection("表") {
            HStack {
                Picker("表", selection: $viewModel.selectedTable) {
                    ForEach(viewModel.tables) { table in
                        Text("\(table.name)（\(table.size)）").tag(String?.some(table.path))
                    }
                }
                .labelsHidden()
                .fixedSize()
                if let path = viewModel.selectedTable {
                    Button("開く", systemImage: "arrow.up.forward.square") { openPath(path) }
                        .buttonStyle(.borderless)
                }
            }
            if let head = viewModel.head {
                TableHeadView(head: head)
            }
        }
    }

    private var figures: some View {
        InspectorSection("図（\(viewModel.figures.count)）") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(viewModel.figures) { figure in
                    Button {
                        openPath(figure.path)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            FigureThumbnail(url: figure.url)
                            Text(figure.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 表の先頭の行。
private struct TableHeadView: View {
    let head: TableHeadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("先頭 \(head.rows.count) 行（ファイルは \(head.size)）").font(.caption).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    GridRow {
                        ForEach(Array(head.columns.enumerated()), id: \.offset) { _, column in
                            Text(column).fontWeight(.semibold)
                        }
                    }
                    Divider()
                    ForEach(Array(head.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.prefix(head.columns.count).enumerated()), id: \.offset) { _, value in
                                Text(value).lineLimit(1)
                            }
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
            }
            .frame(maxHeight: 320)
            .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 6))
        }
    }
}

/// 図の小さな見本（読み込みは裏で行う）。
private struct FigureThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.white)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(4)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: 150)
        .task(id: url) {
            let url = url
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
}
