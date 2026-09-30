//
//  GraphCanvasModel+Labels.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import simd

extension GraphCanvasModel {
    /// 重ならなければ出すラベルの数。遠くからは少なく、近づくほど多く。
    var labelBudget: Int {
        let budget = min(max(screenSpacing * 3.2 - 24, 8), 240)
        // まとまりの名前を出しているあいだは、概念の名前を控えめにする
        return Int(budget * (1 - 0.75 * groupLabelAlpha))
    }

    /// ラベルを置いて、描くものを renderer に渡す。
    func updateLabels(elapsed: Float) {
        guard let atlas = renderer?.atlas, !projected.isEmpty else {
            renderer?.labels.write([])
            return
        }
        let ink = GraphPalette.ink(isDark: isDark)
        var candidates: [LabelPlacer.Candidate] = []
        let selected = index(of: selectedNodeID)
        // 1. 選んだ点とホバーしている点は、重なっても出す
        for index in [selected, hoveredIndex].compactMap(\.self) {
            if let candidate = nodeCandidate(index, atlas: atlas, ink: ink.text, emphasis: 2) {
                candidates.append(candidate)
            }
        }
        // 2. 経路、隣、検索の一致
        let path = pathNodeIDs.compactMap { indexByID[$0] }
        let neighbors = selected.map { Array(neighborIndices[$0].prefix(60)) } ?? []
        let matches = highlightedNodeIDs.compactMap { indexByID[$0] }.sorted { importanceRank($0) < importanceRank($1) }
        for index in path + neighbors + matches.prefix(60) {
            if let candidate = nodeCandidate(index, atlas: atlas, ink: ink.text, emphasis: 1) {
                candidates.append(candidate)
            }
        }
        // 3. まとまりの名前（遠くから眺めているとき）
        candidates += groupCandidates(atlas: atlas)
        // 4. 重要な点
        // 重なって置けないものが多いので、出す数の数倍まで試せば足りる
        let half = camera.viewSize / 2 + 40
        var regular = 0
        for index in importanceOrder where emphasized[index] == nil && regular < labelBudget * 4 {
            let screen = projected[index].screen
            guard abs(screen.x) < half.x, abs(screen.y) < half.y,
                let candidate = nodeCandidate(index, atlas: atlas, ink: ink.text, emphasis: 0)
            else { continue }
            candidates.append(candidate)
            regular += 1
        }
        labelPlacer.halo = ink.halo
        let instances = labelPlacer.place(
            candidates, budget: labelBudget, viewport: camera.viewSize, elapsed: elapsed
        ) { [self] key in
            key < projected.count
                ? nodeCandidate(key, atlas: atlas, ink: ink.text, emphasis: 0, allowsHidden: true)
                : groupCandidate(key - projected.count, atlas: atlas)
        }
        labelsAreSettled = labelPlacer.alphas.values.allSatisfy { $0 > 0.985 }
        renderer?.labels.write(instances)
    }

    private func importanceRank(_ index: Int) -> Float {
        -scene.nodes[index].radius
    }

    /// 点のラベル（点の下に置く）。
    private func nodeCandidate(
        _ index: Int, atlas: LabelAtlas, ink: SIMD4<Float>, emphasis: Int, allowsHidden: Bool = false
    ) -> LabelPlacer.Candidate? {
        guard atlas.entries.indices.contains(index) else { return nil }
        let node = projected[index]
        let entry = atlas.entries[index]
        guard entry.size.x > 0, allowsHidden || (node.look.w > 0.6 && node.look.x > 0.2) else { return nil }
        let depth = min(max(node.screen.z, 0.8), 1.25)
        let scale = depth * (emphasis > 0 ? 1.06 : 1)
        let center = SIMD2(node.screen.x, node.screen.y - node.look.y - 2.5 - entry.textSize.y * scale / 2)
        var color = ink
        switch emphasis {
        case 2: color.w = 1
        case 1: color.w = 0.95
        default: color.w = (0.62 + 0.3 * GraphProjection.smoothstep(14, 44, screenSpacing)) * min(node.look.x * 1.3, 1)
        }
        return LabelPlacer.Candidate(
            key: index, center: center, entry: entry, scale: scale, color: color, isForced: emphasis == 2)
    }

    /// まとまりの名前（まとまりの中心に置く）。
    private func groupCandidates(atlas: LabelAtlas) -> [LabelPlacer.Candidate] {
        guard groupLabelAlpha > 0.01 else { return [] }
        return namedGroups.indices
            .sorted { groupSizes[namedGroups[$0].group] > groupSizes[namedGroups[$1].group] }
            .compactMap { groupCandidate($0, atlas: atlas) }
    }

    private func groupCandidate(_ named: Int, atlas: LabelAtlas) -> LabelPlacer.Candidate? {
        guard namedGroups.indices.contains(named) else { return nil }
        let group = namedGroups[named].group
        let entryIndex = projected.count + named
        guard atlas.entries.indices.contains(entryIndex), centroids.indices.contains(group),
            centroids[group].w >= Float(Self.namedGroupMinimumSize) * 0.5
        else { return nil }
        let entry = atlas.entries[entryIndex]
        let screen = camera.project(centroids[group].xyz)
        let groupID = scene.groups[namedGroups[named].entry].id
        var color = GraphPalette.color(for: groupID, isDark: isDark)
        color = isDark ? color * 0.45 + SIMD4(repeating: 0.55) : color * 0.62
        color.w = groupLabelAlpha
        return LabelPlacer.Candidate(
            key: projected.count + named, center: SIMD2(screen.x, screen.y), entry: entry,
            scale: min(max(screen.z, 0.8), 1.2), color: color, isForced: false)
    }
}
