//
//  LibrarySettingsView.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
import SwiftUI

/// 設定の「ライブラリ」。保存先の場所を見せる。
public struct LibrarySettingsView: View {
    private let dataDirectory: URL

    /// - Parameter dataDirectory: ライブラリ（library.store）と PDF（Storage/）を置いているフォルダ。
    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
    }

    public var body: some View {
        Form {
            LabeledContent("保存先") {
                Text(dataDirectory.path(percentEncoded: false))
                    .textSelection(.enabled)
                    .truncationMode(.middle)
            }
            Button("Finder で開く", systemImage: "folder") { NSWorkspace.shared.open(dataDirectory) }
            Text("文献の情報、注釈、メモは library.store に、PDF は Storage フォルダに、文献ごとに分けて置いています。Time Machine のバックアップに入ります。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
