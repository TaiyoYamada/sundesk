//
//  InspectorView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskComposition
import SundeskDomain
import SundeskPresentation
import SundeskRenderer
import SwiftUI

/// 右のインスペクタ。選んでいるファイルの情報、プロパティ、タグ、目次、バックリンクを出す。
struct InspectorView: View {
    let workspace: WorkspaceViewModel
    let pages: RenderedPageCache

    var body: some View {
        if let document = workspace.selectedDocument {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FileSection(document: document)
                    if !document.properties.isEmpty {
                        PropertiesSection(
                            properties: document.properties.filter { $0.key != "tags" && $0.key != "title" })
                    }
                    if !document.tags.isEmpty {
                        TagsSection(tags: document.tags, workspace: workspace)
                    }
                    if let page = pages.existingPage(for: document.path), !page.headings.isEmpty,
                        document.displayMode == .rendered
                    {
                        OutlineSection(page: page)
                    }
                    if document.kind == .markdown || document.kind == .html {
                        BacklinksSection(backlinks: document.backlinks, workspace: workspace)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: document.path) { await document.loadBacklinks() }
        } else {
            ContentUnavailableView("選んでいるファイルはありません", systemImage: "info.circle")
        }
    }
}

// MARK: - 各セクション

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct FileSection: View {
    let document: DocumentViewModel

    var body: some View {
        InspectorSection(title: "ファイル") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                row("名前", document.path.split(separator: "/").last.map(String.init) ?? document.path)
                row("種類", document.kind.displayName)
                if let info = document.document?.info {
                    row("サイズ", info.size.formatted(.byteCount(style: .file)))
                    if let created = info.created {
                        row("作成", created.formatted(date: .abbreviated, time: .shortened))
                    }
                    row("更新", info.modified.formatted(date: .abbreviated, time: .shortened))
                }
                row("場所", document.path)
            }
            .font(.callout)
            Button("Finder で表示", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    VaultSettings.directory().appending(path: document.path)
                ])
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(3)
        }
    }
}

private struct PropertiesSection: View {
    let properties: [NoteProperty]

    var body: some View {
        if !properties.isEmpty {
            InspectorSection(title: "プロパティ") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                    ForEach(properties, id: \.key) { property in
                        GridRow {
                            Text(property.key).foregroundStyle(.secondary)
                            Text(property.value.displayString).textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
            }
        }
    }
}

private struct TagsSection: View {
    let tags: [String]
    let workspace: WorkspaceViewModel

    var body: some View {
        InspectorSection(title: "タグ") {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button("#\(tag)") { workspace.navigatorMode = .tags }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("タグの一覧を開く")
                }
            }
        }
    }
}

private struct OutlineSection: View {
    let page: RenderedPage

    var body: some View {
        InspectorSection(title: "目次") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(page.headings) { heading in
                    Button(heading.text) { page.scroll(to: heading) }
                        .buttonStyle(.plain)
                        .font(heading.level <= 1 ? .callout.weight(.semibold) : .callout)
                        .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 12)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct BacklinksSection: View {
    let backlinks: [NoteSummary]
    let workspace: WorkspaceViewModel

    var body: some View {
        InspectorSection(title: "バックリンク（\(backlinks.count)）") {
            if backlinks.isEmpty {
                Text("このファイルへのリンクはありません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(backlinks) { note in
                        Button {
                            workspace.open(path: note.path)
                        } label: {
                            Label(note.title, systemImage: "arrow.turn.up.left")
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            }
        }
    }
}

/// 横に並べ、はみ出したら折り返す。
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, !last.indices.isEmpty, last.width + spacing + size.width > width {
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let extra = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += extra + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
