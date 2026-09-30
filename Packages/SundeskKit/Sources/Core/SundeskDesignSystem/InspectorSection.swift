//
//  InspectorSection.swift
//  SundeskDesignSystem
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI

/// インスペクタの 1 つのまとまり（小さな見出しと中身）。
public struct InspectorSection<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
