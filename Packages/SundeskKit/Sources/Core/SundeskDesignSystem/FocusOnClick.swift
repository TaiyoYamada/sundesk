//
//  FocusOnClick.swift
//  SundeskDesignSystem
//
//  Created by 山田大陽 on 2026/09/30.
//

import SwiftUI

extension View {
    /// 押したら、キーボードの操作をこの一覧に向ける（Finder と同じく、選んですぐ ⌫ で消せるように）。
    ///
    /// エディタに入力中に一覧の行を押しても、一覧が選ばれるだけで、キーボードはエディタに残ることがある。
    public func focusesOnClick() -> some View {
        modifier(FocusOnClick())
    }
}

private struct FocusOnClick: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
    }
}
