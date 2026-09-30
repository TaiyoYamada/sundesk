//
//  LabelAtlas.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import CoreText
import Metal

/// ラベルの文字を、あらかじめ 1 枚の画像（文字の地図）に描いておく。
///
/// フレームごとに文字を組むと重いので、形を読み込んだときに CoreText で一度だけ描き、
/// 描画では地図から切り出した四角を並べるだけにする。Retina でもくっきり見えるよう、2 倍の大きさで描く。
final class LabelAtlas {
    struct Style: Hashable {
        let size: CGFloat
        let weight: NSFont.Weight

        /// 概念の名前。
        static let concept = Style(size: 11.5, weight: .medium)
        /// まとまりの名前（遠くから眺めたとき）。
        static let group = Style(size: 17, weight: .bold)
    }

    struct Entry: Equatable {
        /// 地図の中の場所（左上と右下、0〜1）。
        let uv: SIMD4<Float>
        /// 四角の大きさ（pt、縁取りの余白を含む）。
        let size: SIMD2<Float>
        /// 文字そのものの大きさ（pt、重なりの判定に使う）。
        let textSize: SIMD2<Float>

        static let empty = Entry(uv: .zero, size: .zero, textSize: .zero)
    }

    let texture: any MTLTexture
    let entries: [Entry]

    static let scale: CGFloat = 2
    /// 縁取りのための余白（pt）。
    static let padding: CGFloat = 3
    static let width = 2048
    static let maxHeight = 16384
    /// これより長い名前は「…」で切る（pt）。
    static let maxTextWidth: CGFloat = 190

    private struct Line {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        var pixelSize: (width: Int, height: Int) {
            (
                Int(((width + LabelAtlas.padding * 2) * LabelAtlas.scale).rounded(.up)),
                Int(((ascent + descent + LabelAtlas.padding * 2) * LabelAtlas.scale).rounded(.up))
            )
        }
    }

    init?(device: any MTLDevice, queue: any MTLCommandQueue, labels: [(text: String, style: Style)]) {
        let lines = labels.map { Self.makeLine($0.text, style: $0.style) }
        var origins: [(x: Int, y: Int)?] = []
        var cursor = (x: 0, y: 0, shelf: 0)
        for line in lines {
            let size = line.pixelSize
            if cursor.x + size.width > Self.width {
                cursor = (0, cursor.y + cursor.shelf, 0)
            }
            guard size.width <= Self.width, cursor.y + size.height <= Self.maxHeight else {
                origins.append(nil)
                continue
            }
            origins.append((cursor.x, cursor.y))
            cursor.x += size.width
            cursor.shelf = max(cursor.shelf, size.height)
        }
        let height = max((cursor.y + cursor.shelf + 3) / 4 * 4, 4)
        guard let pixels = Self.draw(lines, origins: origins, height: height),
            let texture = Self.makeTexture(device: device, queue: queue, pixels: pixels, height: height)
        else { return nil }
        self.texture = texture
        entries = zip(lines, origins).map { line, origin in
            guard let origin else { return .empty }
            let size = line.pixelSize
            let uv = SIMD4(
                Float(origin.x) / Float(Self.width), Float(origin.y) / Float(height),
                Float(origin.x + size.width) / Float(Self.width), Float(origin.y + size.height) / Float(height))
            return Entry(
                uv: uv, size: SIMD2(Float(size.width), Float(size.height)) / Float(Self.scale),
                textSize: SIMD2(Float(line.width), Float(line.ascent + line.descent)))
        }
    }

    private static func makeLine(_ text: String, style: Style) -> Line {
        let font = NSFont.systemFont(ofSize: style.size, weight: style.weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxTextWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(line, maxTextWidth, .end, ellipsis) ?? line
        }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return Line(line: line, width: width, ascent: ascent, descent: descent)
    }

    /// 白い文字を黒地に描いた、1 画素 1 バイトの画像。
    private static func draw(_ lines: [Line], origins: [(x: Int, y: Int)?], height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldSmoothFonts(false)
            context.setFillColor(gray: 1, alpha: 1)
            context.scaleBy(x: scale, y: scale)
            for (line, origin) in zip(lines, origins) {
                guard let origin else { continue }
                let size = line.pixelSize
                // CoreGraphics は左下が原点。地図は上から詰めているので、上下を返す
                let bottom = CGFloat(height - origin.y - size.height) / scale
                context.textPosition = CGPoint(
                    x: CGFloat(origin.x) / scale + padding, y: bottom + padding + line.descent)
                CTLineDraw(line.line, context)
            }
            return true
        }
        return drawn ? pixels : nil
    }

    private static func makeTexture(
        device: any MTLDevice, queue: any MTLCommandQueue, pixels: [UInt8], height: Int
    ) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!,
                bytesPerRow: width)
        }
        if let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
        }
        return texture
    }
}
