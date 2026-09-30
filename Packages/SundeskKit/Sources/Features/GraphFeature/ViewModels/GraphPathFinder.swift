//
//  GraphPathFinder.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

/// 2 つの概念の間の、いちばん近い道（ダイクストラ法）。
///
/// 歩数を主にして、同じ歩数なら強い関係（重い線）を通る道を選ぶ。
enum GraphPathFinder {
    /// 点の添字の列（`start` から `goal` まで）。つながっていなければ nil。
    static func path(from start: Int, to goal: Int, nodeCount: Int, edges: [GraphEdgeItem]) -> [Int]? {
        guard start != goal, (0..<nodeCount).contains(start), (0..<nodeCount).contains(goal) else { return nil }
        var adjacency = [[(node: Int, cost: Double)]](repeating: [], count: nodeCount)
        for edge in edges {
            // 重さは 0.5〜2。重いほど少しだけ近い
            let cost = 1 + 0.25 / max(edge.weight, 0.01)
            adjacency[edge.source].append((edge.target, cost))
            adjacency[edge.target].append((edge.source, cost))
        }
        var distance = [Double](repeating: .infinity, count: nodeCount)
        var previous = [Int?](repeating: nil, count: nodeCount)
        var heap = MinHeap()
        distance[start] = 0
        heap.push((0, start))
        while let (cost, node) = heap.pop() {
            if node == goal { break }
            guard cost <= distance[node] else { continue }
            for (next, step) in adjacency[node] where cost + step < distance[next] {
                distance[next] = cost + step
                previous[next] = node
                heap.push((cost + step, next))
            }
        }
        guard distance[goal].isFinite else { return nil }
        var path = [goal]
        while let before = previous[path[path.count - 1]] {
            path.append(before)
        }
        return path.reversed()
    }
}

/// 小さい順に取り出せる山（二分ヒープ）。
private struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ item: (Double, Int)) {
        items.append(item)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].0 < items[parent].0 else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < items.count, items[left].0 < items[smallest].0 { smallest = left }
            if right < items.count, items[right].0 < items[smallest].0 { smallest = right }
            guard smallest != parent else { break }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top
    }
}
