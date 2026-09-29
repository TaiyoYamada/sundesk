//
//  DocumentInspectorView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskDesignSystem
import SwiftUI

/// インスペクタの中身。ファイルの情報、プロパティ、タグ、目次、バックリンク。
public struct DocumentInspectorView: View {
    private let document: DocumentViewModel
    private let open: (String) -> Void
    private let showTag: (String) -> Void

    /// - Parameters:
    ///   - open: バックリンクを押したときに呼ぶ。
    ///   - showTag: タグを押したときに呼ぶ（ナビゲータにタグのノートを出す）。
    public init(document: DocumentViewModel, open: @escaping (String) -> Void, showTag: @escaping (String) -> Void) {
        self.document = document
        self.open = open
        self.showTag = showTag
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let info = document.fileInfo {
                    fileSection(info)
                }
                if !document.properties.isEmpty {
                    propertiesSection
                }
                if !document.tags.isEmpty {
                    tagsSection
                }
                if !document.outline.isEmpty {
                    outlineSection
                }
                if document.showsBacklinks {
                    backlinksSection
                }
            }
            .padding(14)
        }
        .task(id: document.path) { await document.loadBacklinks() }
    }

    private func fileSection(_ info: FileInfoItem) -> some View {
        InspectorSection("ファイル") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                row("名前", info.name)
                row("種類", info.kind)
                row("サイズ", info.size)
                if let created = info.created {
                    row("作成", created)
                }
                row("更新", info.modified)
                row("場所", info.location)
            }
            .font(.callout)
            Button("Finder で表示", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([document.fileURL])
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

    private var propertiesSection: some View {
        InspectorSection("プロパティ") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach(document.properties) { property in
                    GridRow {
                        Text(property.key).foregroundStyle(.secondary)
                        Text(property.value).textSelection(.enabled)
                    }
                }
            }
            .font(.callout)
        }
    }

    private var tagsSection: some View {
        InspectorSection("タグ") {
            FlowLayout(spacing: 6) {
                ForEach(document.tags, id: \.self) { tag in
                    Button("#\(tag)") { showTag(tag) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("このタグのノートを一覧する")
                }
            }
        }
    }

    private var outlineSection: some View {
        InspectorSection("目次") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(document.outline) { item in
                    Button(item.title) { document.scrollTarget = item }
                        .buttonStyle(.plain)
                        .font(item.level <= 1 ? .callout.weight(.semibold) : .callout)
                        .padding(.leading, CGFloat(max(item.level - 1, 0)) * 12)
                        .lineLimit(2)
                }
            }
        }
    }

    private var backlinksSection: some View {
        InspectorSection("バックリンク（\(document.backlinks.count)）") {
            if document.backlinks.isEmpty {
                Text("このファイルへのリンクはありません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(document.backlinks) { note in
                        Button {
                            open(note.path)
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
