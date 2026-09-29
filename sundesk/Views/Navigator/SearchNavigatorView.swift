//
//  SearchNavigatorView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskComposition
import SundeskDomain
import SundeskPresentation
import SwiftUI

/// ノートのタイトルと本文を検索する。
struct SearchNavigatorView: View {
    let workspace: WorkspaceViewModel
    @State private var search = Container.shared.searchViewModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("ノートを検索", text: $search.query)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .accessibilityIdentifier("search-field")

            if search.hasSearched, search.results.isEmpty {
                ContentUnavailableView.search(text: search.query)
            } else {
                List(search.results) { result in
                    Button {
                        workspace.open(path: result.path)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).fontWeight(.medium)
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .task(id: search.query) { await search.search() }
        .onAppear { isFieldFocused = true }
    }
}
