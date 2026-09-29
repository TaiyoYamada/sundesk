//
//  MathRenderer.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SwiftMath

/// LaTeX の数式を SwiftMath で画像にする。同じ数式は描き直さない。
final class MathRenderer {
    static let shared = MathRenderer()

    struct Rendered {
        let image: NSImage
        /// ベースラインより下の高さ（文の中に置くとき、この分だけ下げる）。
        let descent: CGFloat
    }

    private let cache = NSCache<NSString, Box>()

    private final class Box {
        let value: Rendered?
        init(_ value: Rendered?) { self.value = value }
    }

    /// - Parameter isDark: ダークモードか（画像の文字色を決める）。
    /// - Returns: 読めない数式なら nil。
    func render(_ latex: String, display: Bool, fontSize: CGFloat, isDark: Bool) -> Rendered? {
        let key = "\(display ? "D" : "I")|\(fontSize)|\(isDark)|\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        var math = MathImage(
            latex: latex,
            fontSize: display ? fontSize * 1.15 : fontSize,
            textColor: isDark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.1, alpha: 1),
            labelMode: display ? .display : .text,
            textAlignment: .left
        )
        let (error, image, layout) = math.asImage()
        let rendered = error == nil ? image.map { Rendered(image: $0, descent: layout?.descent ?? 0) } : nil
        cache.setObject(Box(rendered), forKey: key)
        return rendered
    }
}
