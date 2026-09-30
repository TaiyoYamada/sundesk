//
//  ImageItems.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// 画像の縦横比。大きさ（長い辺）と合わせて、幅と高さを決める。
public enum ImageAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case square
    case landscape4x3
    case portrait3x4
    case landscape3x2
    case portrait2x3
    case landscape16x9
    case portrait9x16

    public var id: String { rawValue }

    /// 横と縦の比（横, 縦）。
    public var ratio: (width: Int, height: Int) {
        switch self {
        case .square: (1, 1)
        case .landscape4x3: (4, 3)
        case .portrait3x4: (3, 4)
        case .landscape3x2: (3, 2)
        case .portrait2x3: (2, 3)
        case .landscape16x9: (16, 9)
        case .portrait9x16: (9, 16)
        }
    }

    public var title: String {
        switch self {
        case .square: "1:1 正方形"
        case .landscape4x3: "4:3 横"
        case .portrait3x4: "3:4 縦"
        case .landscape3x2: "3:2 横"
        case .portrait2x3: "2:3 縦"
        case .landscape16x9: "16:9 横長"
        case .portrait9x16: "9:16 縦長"
        }
    }

    /// エンジンが受ける幅と高さの範囲と、そろえる倍数。
    public static let sideRange = 256...2048
    public static let sideMultiple = 16

    /// 長い辺を `longSide` にしたときの幅と高さ。どちらも 16 の倍数で、256〜2048 に収める。
    public func dimensions(longSide: Int) -> ImageDimensions {
        let (width, height) = ratio
        let long = Self.snap(Double(longSide))
        let short = Self.snap(Double(longSide) * Double(min(width, height)) / Double(max(width, height)))
        return width >= height
            ? ImageDimensions(width: long, height: short) : ImageDimensions(width: short, height: long)
    }

    /// 幅と高さに最も近い比。
    public static func closest(width: Int, height: Int) -> ImageAspectRatio {
        let target = Double(width) / Double(max(height, 1))
        return allCases.min { abs(log($0.value / target)) < abs(log($1.value / target)) } ?? .square
    }

    private var value: Double { Double(ratio.width) / Double(ratio.height) }

    private static func snap(_ side: Double) -> Int {
        let multiple = Double(sideMultiple)
        let snapped = Int((side / multiple).rounded()) * sideMultiple
        return min(max(snapped, sideRange.lowerBound), sideRange.upperBound)
    }
}

public struct ImageDimensions: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var label: String { "\(width) × \(height)" }
}

/// クリックのときに押していた修飾キー（Finder と同じ選び方をする）。
public enum SelectionModifier: Sendable {
    /// それだけを選ぶ。
    case none
    /// ⌘: 選んだものに足す、外す。
    case toggle
    /// ⇧: 起点からそこまでを選ぶ。
    case extend
}

public struct ImageModelItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let isDownloaded: Bool

    init(_ option: ImageModelOption) {
        id = option.id
        name = option.name
        isDownloaded = option.isDownloaded
        detail = option.isDownloaded ? "\(option.defaultSteps) ステップ" : "最初に使うときにダウンロードします"
    }
}

public struct ImageItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let prompt: String
    public let model: String
    public let width: Int
    public let height: Int
    public let size: String
    public let seed: Int
    public let steps: String
    public let seconds: String
    public let date: String
    public let isFavorite: Bool
    /// 下に添える、設定の短いまとめ。
    public let summary: String

    init(_ image: GeneratedImage, modelName: String?) {
        id = image.id
        url = URL(filePath: image.path)
        prompt = image.prompt
        model = modelName ?? image.model
        width = image.width
        height = image.height
        size = "\(image.width) × \(image.height)"
        seed = image.seed
        steps = image.steps.map { "\($0)" } ?? "既定"
        seconds = String(format: "%.1f 秒", image.seconds)
        date = image.createdAt.formatted(date: .abbreviated, time: .shortened)
        isFavorite = image.isFavorite
        summary = [model, size, "種 \(image.seed)", image.steps.map { "\($0) ステップ" }, seconds]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}

public struct ProgressItem: Hashable, Sendable {
    public let title: String
    /// 何枚目か、何ステップ目か。
    public let detail: String?
    /// 0〜1（何枚かまとめて作るときは、全体の割合）。分からなければ nil。
    public let fraction: Double?
    public let startedAt: Date
    /// 仕上がりの見込み。分からなければ nil。
    public let estimatedEnd: Date?
    /// 作っている画像の大きさ（ギャラリーの仮の枠に使う）。
    public let width: Int
    public let height: Int
}

extension ProgressItem {
    /// 「残り約 1 分 20 秒」。見込みがなければ nil。
    public func remainingText(now: Date) -> String? {
        guard let estimatedEnd else { return nil }
        let seconds = Int(estimatedEnd.timeIntervalSince(now).rounded())
        return seconds <= 2 ? "まもなく仕上がります" : "残り約 \(Self.duration(seconds))"
    }

    /// 「経過 12 秒」。
    public func elapsedText(now: Date) -> String {
        "経過 \(Self.duration(max(Int(now.timeIntervalSince(startedAt)), 0)))"
    }

    static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}
