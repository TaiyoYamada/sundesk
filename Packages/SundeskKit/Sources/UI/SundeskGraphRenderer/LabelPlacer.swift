//
//  LabelPlacer.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import simd

/// 1 つのラベルの描き方（シェーダーの `LabelInstance` と同じ並び）。
struct LabelInstance: Equatable {
    /// xy = 中心（画面の中央から、pt、上が正）、zw = 大きさ（pt）。
    var rect: SIMD4<Float>
    var uv: SIMD4<Float>
    var color: SIMD4<Float>
    var halo: SIMD4<Float>
}

/// ラベルを置く場所を決める。重なるものは出さず、出し入れはふわっと変える。
///
/// 置く順は、強調した点（選択、ホバー、経路、隣、検索の一致）→ まとまりの名前 → 重要な点。
struct LabelPlacer {
    /// ラベルの候補。
    struct Candidate {
        /// 点なら点の添字、まとまりなら点の数 + まとまりの添字。
        let key: Int
        /// ラベルの中心（画面の中央から、pt、上が正）。
        let center: SIMD2<Float>
        let entry: LabelAtlas.Entry
        let scale: Float
        let color: SIMD4<Float>
        /// 重なっていても出す（選んだ点など）。
        let isForced: Bool
    }

    /// 縁取りの色。
    var halo = SIMD4<Float>.zero
    /// ラベルごとの今の濃さ。
    private(set) var alphas: [Int: Float] = [:]
    private var last: [Int: Candidate] = [:]

    /// 置くラベルを決めて、描くものを返す。
    ///
    /// - Parameters:
    ///   - ordered: 置きたい順の候補。
    ///   - budget: 重ならずに置けても、これ以上は出さない（強制するものは数えない）。
    ///   - elapsed: 前のフレームからの秒数（濃さを変える速さに使う）。
    ///   - current: 消えていく途中のラベルの、今のフレームでの候補（点についていくように）。
    mutating func place(
        _ ordered: [Candidate], budget: Int, viewport: SIMD2<Float>, elapsed: Float, current: (Int) -> Candidate?
    ) -> [LabelInstance] {
        var grid = OccupancyGrid()
        var targets: [Int: Candidate] = [:]
        var placed = 0
        let bounds = viewport / 2 + 40
        for candidate in ordered where targets[candidate.key] == nil {
            guard candidate.isForced || placed < budget else { continue }
            let size: SIMD2<Float> = candidate.entry.textSize * candidate.scale + SIMD2<Float>(6, 2)
            guard abs(candidate.center.x) < bounds.x, abs(candidate.center.y) < bounds.y else { continue }
            let lower: SIMD2<Float> = candidate.center - size / 2
            let upper: SIMD2<Float> = candidate.center + size / 2
            let rect = SIMD4<Float>(lowHalf: lower, highHalf: upper)
            guard candidate.isForced || !grid.intersects(rect) else { continue }
            grid.insert(rect)
            targets[candidate.key] = candidate
            if !candidate.isForced { placed += 1 }
        }

        let step = min(elapsed / 0.18, 1)
        var instances: [LabelInstance] = []
        for key in Set(targets.keys).union(alphas.keys) {
            let target: Float = targets[key] == nil ? 0 : 1
            let alpha = (alphas[key] ?? 0) + (target - (alphas[key] ?? 0)) * step
            guard alpha > 0.01, let candidate = targets[key] ?? current(key) ?? last[key] else {
                alphas[key] = nil
                last[key] = nil
                continue
            }
            alphas[key] = alpha
            last[key] = candidate
            let size = candidate.entry.size * candidate.scale
            var color = candidate.color
            color.w *= alpha
            var haloColor = halo
            haloColor.w *= alpha * min(candidate.color.w * 1.4, 1)
            instances.append(
                LabelInstance(
                    rect: SIMD4(lowHalf: candidate.center, highHalf: size), uv: candidate.entry.uv, color: color,
                    halo: haloColor))
        }
        return instances
    }

    mutating func reset() {
        alphas = [:]
        last = [:]
    }
}

/// 置いた四角を、升目に分けて覚える（重なりを速く調べる）。
struct OccupancyGrid {
    private let cell: Float = 48
    private var cells: [SIMD2<Int32>: [SIMD4<Float>]] = [:]

    func intersects(_ rect: SIMD4<Float>) -> Bool {
        for key in keys(for: rect) {
            for other in cells[key] ?? [] where Self.overlap(rect, other) {
                return true
            }
        }
        return false
    }

    mutating func insert(_ rect: SIMD4<Float>) {
        for key in keys(for: rect) {
            cells[key, default: []].append(rect)
        }
    }

    private func keys(for rect: SIMD4<Float>) -> [SIMD2<Int32>] {
        let lower = SIMD2<Int32>(Int32((rect.x / cell).rounded(.down)), Int32((rect.y / cell).rounded(.down)))
        let upper = SIMD2<Int32>(Int32((rect.z / cell).rounded(.down)), Int32((rect.w / cell).rounded(.down)))
        var keys: [SIMD2<Int32>] = []
        for x in lower.x...max(lower.x, upper.x) {
            for y in lower.y...max(lower.y, upper.y) {
                keys.append(SIMD2(x, y))
            }
        }
        return keys
    }

    private static func overlap(_ first: SIMD4<Float>, _ second: SIMD4<Float>) -> Bool {
        first.x < second.z && second.x < first.z && first.y < second.w && second.y < first.w
    }
}
