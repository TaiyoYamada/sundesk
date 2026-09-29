//
//  TabBarView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

/// エディタのタブ（Xcode や Safari と同じく、横に並べる）。
struct TabBarView: View {
    let workspace: WorkspaceViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(workspace.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isSelected: tab.id == workspace.selectedTabID,
                        select: { workspace.selectedTabID = tab.id },
                        close: { workspace.close(tab.id) }
                    )
                    Divider().frame(height: 18)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 32)
        .background(.bar)
    }
}

private struct TabItemView: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.systemImage)
                .imageScale(.small)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(tab.title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Button(action: close) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("タブを閉じる")
            .accessibilityLabel("\(tab.title) を閉じる")
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 110, maxWidth: 220, maxHeight: .infinity)
        .background(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("タブを閉じる", action: close)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor-tab")
        .accessibilityLabel(tab.title)
    }
}
