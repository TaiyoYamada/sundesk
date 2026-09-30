//
//  TagNavigatorView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI

/// タグの一覧。タグを選ぶと、そのタグのノートが下に出る。
public struct TagNavigatorView: View {
    @Bindable private var tags: TagsViewModel
    private let open: (String) -> Void

    public init(tags: TagsViewModel, open: @escaping (String) -> Void) {
        self.tags = tags
        self.open = open
    }

    public var body: some View {
        List(selection: $tags.selectedTag) {
            Section("タグ") {
                ForEach(tags.tags) { tag in
                    HStack {
                        Label(tag.name, systemImage: "number")
                        Spacer()
                        Text(tag.count, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(tag.name)
                }
            }
            if let selected = tags.selectedTag {
                Section("#\(selected) のノート") {
                    ForEach(tags.notes) { note in
                        Button {
                            open(note.path)
                        } label: {
                            Label(note.title, systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if tags.tags.isEmpty {
                ContentUnavailableView(
                    "タグがありません",
                    systemImage: "tag",
                    description: Text("ノートのフロントマターか本文に #タグ を書くと、ここに並びます。")
                )
            }
        }
        .task { await tags.observe() }
        .task(id: tags.selectedTag) { await tags.loadNotes() }
    }
}
