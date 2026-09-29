//
//  GraphColors.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

import SwiftUI

/// コミュニティの色（グラフの点と同じ色を、凡例やインスペクタで使う）。
public enum GraphColors {
    public static func color(for group: Int) -> Color {
        let value = GraphPalette.color(for: group)
        return Color(.sRGB, red: Double(value.x), green: Double(value.y), blue: Double(value.z))
    }
}
