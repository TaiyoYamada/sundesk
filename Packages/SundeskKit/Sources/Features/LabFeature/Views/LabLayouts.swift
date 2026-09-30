//
//  LabLayouts.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import SundeskDesignSystem
import SwiftUI

/// 道具の画面の枠。広ければ左に設定・右に結果、狭ければ（パネルに入れたとき）上に設定・下に結果を並べる。
struct AdaptiveSplit<Settings: View, Result: View>: View {
    /// 横に並べるときの、設定の幅。
    let settingsWidth: CGFloat
    @ViewBuilder let settings: Settings
    @ViewBuilder let result: Result
    @State private var width: CGFloat = 0

    private var isWide: Bool { width >= settingsWidth + 360 }

    var body: some View {
        Group {
            if isWide {
                HStack(alignment: .top, spacing: 0) {
                    settings.frame(width: settingsWidth)
                    Divider()
                    result.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                SplitPane(.vertical, fraction: 0.5, minFirst: 140, minSecond: 140) {
                    settings
                } second: {
                    result.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }
}

/// 横の境目をドラッグして、右のパネルの幅を変えるつまみ。
struct PanelResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var start: Double?

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(.rect)
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let origin = start ?? width
                                start = origin
                                width = min(max(origin - value.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// 選んだものを消す前に、件数を示して確かめる（Finder と同じく ⌫ や右クリックのメニューから呼ぶ）。
    /// - Parameters:
    ///   - pending: 消そうとしているもの。nil でなくなると確かめる。
    ///   - title: 確かめる文（消すものから作る）。
    func confirmsDeletion<ID: Hashable>(
        _ pending: Binding<Set<ID>?>, title: @escaping (Set<ID>) -> String, delete: @escaping (Set<ID>) -> Void
    ) -> some View {
        alert(
            pending.wrappedValue.map(title) ?? "",
            isPresented: Binding(
                get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            presenting: pending.wrappedValue
        ) { ids in
            Button("削除", role: .destructive) { delete(ids) }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("この操作は取り消せません。")
        }
    }
}

/// 消す前に確かめる文。
enum DeletionTitle {
    /// 1 つなら名前で、複数なら件数で聞く。
    static func make(count: Int, unit: String, noun: String, name: String?) -> String {
        if count == 1, let name { return "「\(name)」を削除しますか？" }
        return "\(count) \(unit)の\(noun)を削除しますか？"
    }
}
