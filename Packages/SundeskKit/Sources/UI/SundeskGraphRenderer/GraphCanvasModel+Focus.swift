//
//  GraphCanvasModel+Focus.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import simd

extension GraphCanvasModel {
    /// 選んだ点の周りに寄せる隣の数（多すぎると輪が混み合うので、重い線の順に）。
    static let lensLimit = 130

    /// 強調する点（選択、隣、経路、検索の一致）と、強調する線を決め直す。
    func updateEmphasis() {
        emphasisNeedsUpdate = false
        let selected = index(of: selectedNodeID)
        let path = pathNodeIDs.compactMap { indexByID[$0] }
        var emphasis: [Int: Float] = [:]
        for id in highlightedNodeIDs { if let index = indexByID[id] { emphasis[index] = 1 } }
        for index in path { emphasis[index] = 1 }
        var edges: [EdgeData] = []
        for (first, second) in zip(path, path.dropFirst()) {
            edges.append(EdgeData(source: UInt32(first), target: UInt32(second), weight: 1, kind: 2))
        }
        if let selected, path.isEmpty {
            // 経路を出しているあいだは、経路だけを目立たせる
            for neighbor in neighborIndices[selected] {
                emphasis[neighbor] = max(emphasis[neighbor] ?? 0, 1)
                edges.append(EdgeData(source: UInt32(selected), target: UInt32(neighbor), weight: 1, kind: 1))
            }
        }
        if let selected { emphasis[selected] = 2 }
        if let hoveredIndex, hoveredIndex != selected, selected == nil {
            for neighbor in neighborIndices[hoveredIndex].prefix(60) {
                edges.append(EdgeData(source: UInt32(hoveredIndex), target: UInt32(neighbor), weight: 1, kind: 1))
            }
        }
        emphasized = emphasis
        emphasisChangedSinceOrder = true
        lensTargets = path.isEmpty ? Set(selected.map { Array(neighborIndices[$0].prefix(Self.lensLimit)) } ?? []) : []
        renderer?.emphasisEdges.write(edges)
    }

    /// 点ごとの濃さ、強調、ホバー、寄せ方を少しずつ目標へ近づける。動いているあいだ true。
    func updateNodeStates(elapsed: Float, now: Double) -> Bool {
        guard !states.isEmpty else { return false }
        let hasFocus = !emphasized.isEmpty
        let focusGoal: Float = hasFocus ? 1 : 0
        focusAmount += (focusGoal - focusAmount) * min(elapsed * 8, 1)
        var animating = abs(focusGoal - focusAmount) > 0.002
        let dim: Float = isDark ? 0.12 : 0.16
        let selected = index(of: selectedNodeID)
        let lens = lensGoals(around: selected)
        let fade = min(elapsed * 9, 1)
        let hoverFade = min(elapsed * 14, 1)
        let sinceSelection = selectionTime.map { Float(now - $0) } ?? -1
        for index in states.indices {
            var state = states[index]
            let alphaGoal: Float = hasFocus && emphasized[index] == nil ? dim : 1
            let hoverGoal: Float = hoveredIndex == index ? 1 : 0
            state.anim.x += (alphaGoal - state.anim.x) * fade
            state.anim.y = emphasized[index] ?? 0
            state.anim.z += (hoverGoal - state.anim.z) * hoverFade
            state.anim.w = index == selected && sinceSelection >= 0 && sinceSelection < 0.7 ? sinceSelection : -1
            if abs(alphaGoal - state.anim.x) > 0.003 || abs(hoverGoal - state.anim.z) > 0.003 || state.anim.w >= 0 {
                animating = true
            }
            if let goal = lens[index] { state.lens = SIMD4(goal, state.lens.w) }
            if springLens(&state, index: index, goal: lens[index] == nil ? 0 : 1, elapsed: elapsed) {
                animating = true
            }
            states[index] = state
        }
        return animating
    }

    /// 寄せる割合を、ばねで目標へ近づける（少し行き過ぎて戻る、やわらかい動き）。動いているあいだ true。
    private func springLens(_ state: inout NodeState, index: Int, goal: Float, elapsed: Float) -> Bool {
        var weight = state.lens.w
        var velocity = lensVelocities[index]
        guard abs(goal - weight) > 0.0005 || abs(velocity) > 0.0005 else {
            state.lens.w = goal
            lensVelocities[index] = 0
            return false
        }
        let steps = max(Int((elapsed * 240).rounded(.up)), 1)
        let step = elapsed / Float(steps)
        for _ in 0..<steps {
            velocity += (110 * (goal - weight) - 15 * velocity) * step
            weight += velocity * step
        }
        state.lens.w = min(max(weight, -0.2), 1.25)
        lensVelocities[index] = velocity
        return true
    }

    /// 隣を寄せる先。選んだ点の周りの同心円に、強い関係ほど内側に並べる。
    ///
    /// 円ごとに、今の向きの順を保ったまま等しい間隔で並べる（どちらの方向にあったかが分かるように）。
    /// 円は画面に向けて置く（3 次元で回しても、正面を向いたまま）。
    func lensGoals(around selected: Int?) -> [Int: SIMD3<Float>] {
        guard let selected, !lensTargets.isEmpty, positions.indices.contains(selected) else { return [:] }
        let focus = positions[selected].xyz
        let rotation = camera.rotation
        let inverse = rotation.transpose
        // neighborIndices は重い順なので、その順に内側の円から詰める
        var remaining = neighborIndices[selected].filter { lensTargets.contains($0) }[...]
        var goals: [Int: SIMD3<Float>] = [:]
        var ring = 0
        // 円の大きさは、選んだときの拡大の度合いで決める（近づけば広がり、遠ざかっても小さくなりすぎない）
        let zoom = min(camera.zoom, lensZoom ?? camera.zoom)
        let spacing = max(30, 20 * nodeScale + 10)
        while !remaining.isEmpty {
            let radius: Float = 92 + 46 * Float(ring)
            let capacity = max(Int(2 * .pi * radius / spacing), 1)
            let members = Array(remaining.prefix(capacity))
            remaining = remaining.dropFirst(capacity)
            for (member, angle) in Self.spreadEvenly(
                members,
                angles: members.map { index in
                    let view = rotation * (positions[index].xyz - focus)
                    return atan2(view.y, view.x)
                })
            {
                let offset = SIMD3(cos(angle), sin(angle), 0) * (radius / zoom)
                goals[member] = focus + inverse * offset
            }
            ring += 1
        }
        return goals
    }

    /// 向きの順を保ったまま、円の上に等しい間隔で並べ直す（動く量がいちばん少ない回し方で）。
    static func spreadEvenly(_ members: [Int], angles: [Float]) -> [(Int, Float)] {
        let order = members.indices.sorted { angles[$0] < angles[$1] }
        let count = Float(order.count)
        var sine: Float = 0
        var cosine: Float = 0
        for (rank, member) in order.enumerated() {
            let offset = angles[member] - 2 * .pi * Float(rank) / count
            sine += sin(offset)
            cosine += cos(offset)
        }
        let base = atan2(sine, cosine)
        return order.enumerated().map { rank, member in (members[member], base + 2 * .pi * Float(rank) / count) }
    }
}
