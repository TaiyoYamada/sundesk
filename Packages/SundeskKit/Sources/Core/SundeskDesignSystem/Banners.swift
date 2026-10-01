//
//  Banners.swift
//  SundeskDesignSystem
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI

/// 時間のかかる処理の進み具合を、画面の上に帯で出す。
public struct ProgressBanner: View {
    private let title: String
    private let fraction: Double?

    /// - Parameter fraction: 0〜1。分からなければ nil（くるくる回る表示）。
    public init(title: String, fraction: Double?) {
        self.title = title
        self.fraction = fraction
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let fraction {
                ProgressView(value: fraction).frame(width: 120)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// 失敗を、画面の上に帯で出す。
public struct ErrorBanner: View {
    private let message: String
    private let dismiss: () -> Void

    public init(message: String, dismiss: @escaping () -> Void) {
        self.message = message
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer()
            Button("閉じる", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.1))
    }
}
