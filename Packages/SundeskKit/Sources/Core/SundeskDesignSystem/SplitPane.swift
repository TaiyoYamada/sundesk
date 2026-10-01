//
//  SplitPane.swift
//  SundeskDesignSystem
//
//  Created by 山田大陽 on 2026/09/30.
//

import SwiftUI

/// 2 つの領域を、境目をドラッグして大きさを変えられるように並べる。
///
/// `HSplitView` と `VSplitView` は AppKit の分割ビューに包まれ、中身の最小の大きさを毎回問い合わせる。
/// 中にテキストエディタ（NSTextView）があると、最小の大きさが変わり続けて制約の計算が終わらず、
/// アプリが落ちる。ここでは領域の大きさを外から決めて渡すので、中身の大きさに振り回されない。
public struct SplitPane<First: View, Second: View>: View {
    public enum Axis: Sendable {
        /// 左右に並べる。
        case horizontal
        /// 上下に並べる。
        case vertical
    }

    private let axis: Axis
    private let minFirst: CGFloat
    private let minSecond: CGFloat
    private let first: First
    private let second: Second

    @State private var fraction: Double
    @State private var dragStart: Double?

    /// - Parameters:
    ///   - fraction: はじめの、1 つめの領域の割合。
    ///   - minFirst: 1 つめの領域の最小の幅（上下なら高さ）。
    ///   - minSecond: 2 つめの領域の最小の幅（上下なら高さ）。
    public init(
        _ axis: Axis, fraction: Double = 0.5, minFirst: CGFloat = 160, minSecond: CGFloat = 160,
        @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second
    ) {
        self.axis = axis
        self.minFirst = minFirst
        self.minSecond = minSecond
        self.first = first()
        self.second = second()
        _fraction = State(initialValue: fraction)
    }

    public var body: some View {
        GeometryReader { proxy in
            let total = axis == .horizontal ? proxy.size.width : proxy.size.height
            let length = firstLength(total: total)
            if axis == .horizontal {
                HStack(spacing: 0) {
                    first.frame(width: length).frame(maxHeight: .infinity)
                    handle(total: total)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(height: length).frame(maxWidth: .infinity)
                    handle(total: total)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func firstLength(total: CGFloat) -> CGFloat {
        let upper = max(total - minSecond - 1, minFirst)
        return min(max(total * fraction, minFirst), upper).rounded()
    }

    private func handle(total: CGFloat) -> some View {
        Divider()
            .overlay {
                // 線は細いまま、つかめる範囲だけ広げる
                Color.clear
                    .frame(width: axis == .horizontal ? 8 : nil, height: axis == .vertical ? 8 : nil)
                    .contentShape(.rect)
                    .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
                    .gesture(drag(total: total))
            }
            .accessibilityHidden(true)
    }

    private func drag(total: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard total > 0 else { return }
                let start = dragStart ?? Double(firstLength(total: total) / total)
                dragStart = start
                let moved = axis == .horizontal ? value.translation.width : value.translation.height
                fraction = min(max(start + moved / total, 0), 1)
            }
            .onEnded { _ in dragStart = nil }
    }
}
