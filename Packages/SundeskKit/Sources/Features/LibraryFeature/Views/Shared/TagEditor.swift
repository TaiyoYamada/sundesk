//
//  TagEditor.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SundeskDesignSystem
import SwiftUI

/// タグを並べ、足したり外したりする。
struct TagEditor: View {
    let tags: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button("「\(tag)」を外す", systemImage: "xmark") { onRemove(tag) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .imageScale(.small)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
            TextField("タグを足す", text: $newTag)
                .onSubmit {
                    onAdd(newTag)
                    newTag = ""
                }
        }
    }
}
