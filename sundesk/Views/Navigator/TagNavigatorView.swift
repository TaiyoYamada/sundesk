//
//  TagNavigatorView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskComposition
import SundeskDomain
import SundeskPresentation
import SwiftUI

/// タグの一覧。タグを選ぶと、そのタグのノートが下に出る。
struct TagNavigatorView: View {
    let workspace: WorkspaceViewModel
    @State private var tags = Container.shared.tagsViewModel()

    var body: some View {
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
                            workspace.open(path: note.path)
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
                    "タグがありません", systemImage: "tag", description: Text("ノートのフロントマターか本文に #タグ を書くと、ここに並びます。"))
            }
        }
        .task { await tags.observe() }
        .task(id: tags.selectedTag) { await tags.loadNotes() }
    }
}
