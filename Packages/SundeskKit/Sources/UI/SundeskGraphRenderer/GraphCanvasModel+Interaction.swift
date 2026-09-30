//
//  GraphCanvasModel+Interaction.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import simd

extension GraphCanvasModel {
    /// 押した場所にある点（添字）。3 次元では手前の点を選ぶ。`point` は View の座標（左下が原点）。
    func hitTest(_ point: CGPoint) -> Int? {
        let target = centered(point)
        // 手前（奥行きが大きい）ほど、同じ奥行きなら近いほど優先する
        var best: (index: Int, rank: SIMD2<Float>)?
        for (index, node) in projected.enumerated() where node.look.x > 0.05 && node.look.w > 0.5 {
            let distance = simd_distance(SIMD2(node.screen.x, node.screen.y), target)
            guard distance <= node.look.y + 4 else { continue }
            let rank = SIMD2(node.screen.w, -distance)
            if let current = best, (rank.x, rank.y) <= (current.rank.x, current.rank.y) { continue }
            best = (index, rank)
        }
        return best?.index
    }

    /// カーソルの下の点を目立たせる。
    func hover(at point: CGPoint?) {
        let index = point.flatMap(hitTest)
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        emphasisDidChange()
    }

    var isHoveringNode: Bool { hoveredIndex != nil }

    /// 点を押した。⇧ を押していて、すでに選んだ点があれば、そこからの経路をたどる。
    func click(at point: CGPoint, extending: Bool) {
        let nodeID = hitTest(point).map { scene.nodes[$0].id }
        if extending, let nodeID, let selectedNodeID, nodeID != selectedNodeID {
            onPathTarget?(nodeID)
            return
        }
        if !pathNodeIDs.isEmpty { onPathTarget?(nil) }
        select(nodeID: nodeID)
        onSelect?(nodeID)
    }

    /// 点をダブルクリックした（その概念が出てくるノートを開く）。
    func doubleClick(at point: CGPoint) {
        guard let index = hitTest(point) else {
            fitAll()
            return
        }
        let nodeID = scene.nodes[index].id
        if selectedNodeID != nodeID {
            select(nodeID: nodeID)
            onSelect?(nodeID)
        }
        onOpen?(nodeID)
    }

    /// 点をドラッグして置き直す。`point` は View の座標。
    func drag(node index: Int, to point: CGPoint) {
        guard positions.indices.contains(index), projected.indices.contains(index) else { return }
        let node = projected[index]
        let delta = centered(point) - SIMD2(node.screen.x, node.screen.y)
        let scale = max(node.screen.z, 0.05)
        let moved = positions[index].xyz + camera.worldOffset(forScreen: delta / scale)
        renderer?.layout.pin(index, at: moved)
        needsFrame = true
    }

    func release(node index: Int) {
        renderer?.layout.pin(index, at: nil)
        needsFrame = true
    }

    // MARK: - キーボード

    /// 矢印の向きにある隣の点へ移る。何も選んでいなければ、画面の中央に近い重要な点を選ぶ。
    func moveSelection(toward direction: SIMD2<Float>) {
        guard let selected = index(of: selectedNodeID), projected.indices.contains(selected) else {
            let visible = importanceOrder.prefix(30).min { first, second in
                length(projected[first].screen) < length(projected[second].screen)
            }
            if let visible { choose(visible) }
            return
        }
        let origin = SIMD2(projected[selected].screen.x, projected[selected].screen.y)
        func score(_ index: Int) -> Float? {
            let offset = SIMD2(projected[index].screen.x, projected[index].screen.y) - origin
            let distance = simd_length(offset)
            guard distance > 1, projected[index].look.w > 0.5 else { return nil }
            let alignment = simd_dot(offset / distance, direction)
            return alignment > 0.3 ? alignment - distance / 2000 : nil
        }
        let neighbors = neighborIndices[selected].compactMap { index in score(index).map { (index, $0) } }
        let candidates =
            neighbors.isEmpty
            ? projected.indices.compactMap { index in score(index).map { (index, $0 - 0.5) } } : neighbors
        if let best = candidates.max(by: { $0.1 < $1.1 }) { choose(best.0) }
    }

    private func choose(_ index: Int) {
        let nodeID = scene.nodes[index].id
        select(nodeID: nodeID)
        onSelect?(nodeID)
    }

    /// Esc: 経路があれば消し、なければ選択を外す。
    func escape() {
        if !pathNodeIDs.isEmpty {
            onPathTarget?(nil)
        } else if selectedNodeID != nil {
            select(nodeID: nil)
            onSelect?(nil)
        } else if timelineCursor != nil {
            closeTimeline()
        }
    }

    /// Return: 選んだ概念が出てくるノートを開く。
    func openSelection() {
        if let selectedNodeID { onOpen?(selectedNodeID) }
    }
}

private func length(_ value: SIMD4<Float>) -> Float {
    simd_length(SIMD2(value.x, value.y))
}
