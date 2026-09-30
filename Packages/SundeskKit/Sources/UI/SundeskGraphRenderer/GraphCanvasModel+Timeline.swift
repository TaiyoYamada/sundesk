//
//  GraphCanvasModel+Timeline.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

extension GraphCanvasModel {
    /// 最初から最後まで再生する秒数。
    static let timelineDuration: Double = 20

    /// 点に生まれた時があるか（時間を再生できるか）。
    public var hasTimeline: Bool { scene.nodes.contains { $0.birth != nil } }

    /// 知識が育つ様子を再生する。終わりまで来ていれば、最初から。
    public func playTimeline() {
        guard hasTimeline else { return }
        if timelineCursor == nil || (timelineCursor ?? 0) >= 1 {
            timelineCursor = 0
            if flight == nil { fitAll() }
        }
        isPlayingTimeline = true
        updateVisibleCount()
        needsFrame = true
    }

    public func pauseTimeline() {
        isPlayingTimeline = false
    }

    /// 再生の位置を動かす（0〜1）。
    public func setTimelineCursor(_ value: Double) {
        timelineCursor = min(max(value, 0), 1)
        isPlayingTimeline = false
        updateVisibleCount()
        needsFrame = true
    }

    /// 再生をやめて、すべてを出す。
    public func closeTimeline() {
        timelineCursor = nil
        isPlayingTimeline = false
        updateVisibleCount()
        needsFrame = true
    }

    /// 再生を進める。進めているあいだ true。
    func updateTimeline(elapsed: Float) -> Bool {
        guard isPlayingTimeline, let cursor = timelineCursor else { return false }
        let next = min(cursor + Double(elapsed) / Self.timelineDuration, 1)
        timelineCursor = next
        if next >= 1 { isPlayingTimeline = false }
        updateVisibleCount()
        return true
    }

    private func updateVisibleCount() {
        let count: Int
        if let cursor = timelineCursor.map(Float.init) {
            count = scene.nodes.count { ($0.birth ?? 0) <= cursor }
        } else {
            count = scene.nodes.count
        }
        if count != visibleNodeCount { visibleNodeCount = count }
    }
}
