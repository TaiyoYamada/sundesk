//
//  GenerationEstimator.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// 何枚かまとめて作るときの、仕上がりまでの時間の見込み。
///
/// ステップの間隔から 1 ステップの時間を測り、残りのステップと残りの枚数に掛ける。
/// 1 枚目はモデルの読み込みを含むので、2 枚目からは前の 1 枚にかかった時間も使う。
struct GenerationEstimator {
    let count: Int
    private(set) var index = 0
    private var imageStartedAt: Date
    private var firstStepAt: Date?
    private var loadedInThisImage = false
    /// 読み込みを含まない 1 枚の時間（測れたら）。
    private var lastImageSeconds: Double?
    /// 1 ステップの時間（測れたら）。
    private var secondsPerStep: Double?
    private var totalSteps: Int?
    /// 前に同じ設定で作ったときの 1 枚の時間（まだ何も測れていないときに使う）。
    private let previousSeconds: Double?

    init(count: Int, startedAt: Date, previousSeconds: Double?) {
        self.count = max(count, 1)
        imageStartedAt = startedAt
        self.previousSeconds = previousSeconds
    }

    /// 次の 1 枚を始める。
    mutating func startImage(_ index: Int, at date: Date) {
        if self.index != index, !loadedInThisImage {
            lastImageSeconds = date.timeIntervalSince(imageStartedAt)
        }
        self.index = index
        imageStartedAt = date
        firstStepAt = nil
        loadedInThisImage = false
    }

    /// モデルを読み込み始めた（この 1 枚の時間は、見込みに使わない）。
    mutating func loading() {
        loadedInThisImage = true
    }

    /// `step` 番目のステップが終わった。
    mutating func step(_ step: Int, of total: Int, at date: Date) {
        totalSteps = total
        if step <= 1 || firstStepAt == nil {
            firstStepAt = date
            // 1 ステップ目は、文の読み込みなどを含むので長めに出る。2 ステップ目で測り直す
            if secondsPerStep == nil { secondsPerStep = date.timeIntervalSince(imageStartedAt) }
        } else if let firstStepAt {
            secondsPerStep = date.timeIntervalSince(firstStepAt) / Double(step - 1)
        }
    }

    /// 全体の割合（0〜1）。
    func fraction(step: Int, of total: Int) -> Double {
        let current = total > 0 ? Double(min(step, total)) / Double(total) : 0
        return (Double(index) + current) / Double(count)
    }

    /// 仕上がりの見込み。
    func estimatedEnd(now: Date, step: Int? = nil) -> Date? {
        let remainingImages = Double(count - index - 1)
        if let secondsPerStep, let totalSteps {
            let current = secondsPerStep * Double(totalSteps - min(step ?? 0, totalSteps))
            let perImage = lastImageSeconds ?? (secondsPerStep * Double(totalSteps))
            return now.addingTimeInterval(current + perImage * remainingImages)
        }
        if let perImage = lastImageSeconds ?? previousSeconds, !loadedInThisImage || lastImageSeconds != nil {
            let elapsed = now.timeIntervalSince(imageStartedAt)
            return now.addingTimeInterval(max(perImage - elapsed, 0) + perImage * remainingImages)
        }
        return nil
    }
}
