//
//  GraphColors.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftUI

/// まとまりの色（グラフの点と同じ色を、凡例やインスペクタで使う）。ライトとダークで色を変える。
public enum GraphColors {
    /// - Parameter group: まとまりの番号（大きい順に 0 から）。色の数より後ろと負の数は、落ち着いた灰色にする。
    public static func color(for group: Int) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let value = GraphPalette.color(for: group, isDark: isDark)
                return NSColor(srgbRed: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: 1)
            })
    }
}

/// 色の決まり。彩度を抑え、ダークでは明るく、ライトでは深い色にする。
enum GraphPalette {
    /// ダークで使う色（夜空の星のような、明るく柔らかい色）。
    static let dark: [SIMD4<Float>] = [
        rgb(0x7A, 0xA2, 0xF7), rgb(0xE0, 0xAF, 0x68), rgb(0x9E, 0xCE, 0x6A), rgb(0xF7, 0x76, 0x8E),
        rgb(0xBB, 0x9A, 0xF7), rgb(0x7D, 0xCF, 0xFF), rgb(0xFF, 0x9E, 0x64), rgb(0x73, 0xDA, 0xCA),
        rgb(0xE6, 0xC3, 0x84), rgb(0xD2, 0x7E, 0x99), rgb(0x98, 0xBB, 0x6C), rgb(0x9C, 0xAB, 0xCA),
    ]

    /// ライトで使う色（紙に置いたインクのような、深い色）。
    static let light: [SIMD4<Float>] = [
        rgb(0x35, 0x6A, 0xCF), rgb(0xB9, 0x7A, 0x16), rgb(0x4A, 0x93, 0x2B), rgb(0xCC, 0x46, 0x60),
        rgb(0x7F, 0x52, 0xC4), rgb(0x23, 0x8D, 0xB0), rgb(0xD0, 0x66, 0x28), rgb(0x1F, 0x98, 0x85),
        rgb(0xA0, 0x82, 0x2C), rgb(0xA9, 0x52, 0x75), rgb(0x6A, 0x8A, 0x37), rgb(0x5A, 0x67, 0x94),
    ]

    static let neutralDark = rgb(0x8A, 0x90, 0x9C)
    static let neutralLight = rgb(0x8E, 0x92, 0x9A)

    static func color(for group: Int, isDark: Bool) -> SIMD4<Float> {
        let colors = isDark ? dark : light
        guard group >= 0, group < colors.count else { return isDark ? neutralDark : neutralLight }
        return colors[group]
    }

    /// 背景（中央と端）。
    static func background(isDark: Bool) -> (SIMD4<Float>, SIMD4<Float>) {
        isDark ? (rgb(0x14, 0x17, 0x1F), rgb(0x0A, 0x0B, 0x10)) : (rgb(0xFB, 0xFA, 0xF7), rgb(0xEE, 0xEC, 0xE6))
    }

    /// 文字の色と縁取りの色。
    static func ink(isDark: Bool) -> (text: SIMD4<Float>, halo: SIMD4<Float>) {
        isDark ? (rgb(0xE8, 0xEA, 0xF0), rgb(0x0E, 0x10, 0x16)) : (rgb(0x22, 0x24, 0x2A), rgb(0xFA, 0xF9, 0xF6))
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> SIMD4<Float> {
        SIMD4(Float(red) / 255, Float(green) / 255, Float(blue) / 255, 1)
    }
}
