//
//  AppearanceRefresh.swift
//  SundeskDesignSystem
//
//  Created by 山田大陽 on 2026/09/30.
//

import SwiftUI

extension View {
    /// 外観（ライトとダーク）が変わったら作り直す。
    ///
    /// Swift Charts は、アプリの中で外観を切り替えたとき、軸の文字の色を古いまま残す（背景と同じ色になって消える）。
    public func rebuildsOnAppearanceChange() -> some View {
        modifier(AppearanceRefresh())
    }
}

private struct AppearanceRefresh: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.id(colorScheme)
    }
}
