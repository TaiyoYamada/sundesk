//
//  GenerationEstimatorTests.swift
//  ImagesFeatureTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import Testing

@testable import ImagesFeature

@Suite("GenerationEstimator")
struct GenerationEstimatorTests {
    private let start = Date(timeIntervalSince1970: 0)

    private func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test("ステップの間隔から、残りの時間を見込む")
    func estimatesFromSteps() throws {
        var estimator = GenerationEstimator(count: 1, startedAt: start, previousSeconds: nil)
        #expect(estimator.estimatedEnd(now: start) == nil)

        estimator.step(1, of: 4, at: at(5))
        estimator.step(2, of: 4, at: at(8))

        // 1 ステップ 3 秒で、残り 2 ステップ
        let end = try #require(estimator.estimatedEnd(now: at(8), step: 2))
        #expect(end.timeIntervalSince(at(8)) == 6)
        #expect(estimator.fraction(step: 2, of: 4) == 0.5)
    }

    @Test("何枚か作るときは、残りの枚数ぶんも足す")
    func estimatesBatch() throws {
        var estimator = GenerationEstimator(count: 3, startedAt: start, previousSeconds: nil)
        estimator.step(1, of: 2, at: at(2))
        estimator.step(2, of: 2, at: at(4))
        // 1 枚目は 5 秒で仕上がった
        estimator.startImage(1, at: at(5))

        #expect(estimator.fraction(step: 0, of: 2) == 1.0 / 3)
        let end = try #require(estimator.estimatedEnd(now: at(5), step: 0))
        // 今の 1 枚は 2 ステップ × 2 秒、残りの 1 枚は前の 1 枚と同じ 5 秒
        #expect(end.timeIntervalSince(at(5)) == 9)
    }

    @Test("まだ何も測れていなければ、前に同じ設定で作ったときの時間を使う")
    func usesPreviousRecord() throws {
        let estimator = GenerationEstimator(count: 2, startedAt: start, previousSeconds: 10)

        let end = try #require(estimator.estimatedEnd(now: at(4)))
        #expect(end.timeIntervalSince(at(4)) == 16)
    }

    @Test("残りの時間を言葉にする")
    func describesRemaining() {
        let progress = ProgressItem(
            title: "生成しています", detail: nil, fraction: 0.5, startedAt: start, estimatedEnd: at(95), width: 512,
            height: 512)

        #expect(progress.remainingText(now: at(10)) == "残り約 1 分 25 秒")
        #expect(progress.remainingText(now: at(80)) == "残り約 15 秒")
        #expect(progress.remainingText(now: at(94)) == "まもなく仕上がります")
        #expect(progress.elapsedText(now: at(12)) == "経過 12 秒")
    }
}
