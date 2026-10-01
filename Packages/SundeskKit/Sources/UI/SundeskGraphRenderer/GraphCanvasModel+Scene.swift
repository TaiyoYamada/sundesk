//
//  GraphCanvasModel+Scene.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import simd

extension GraphCanvasModel {
    /// 雲を描くまとまりの、最小の点の数。
    static let cloudMinimumSize = 5
    /// 名前を出すまとまりの、最小の点の数。
    static let namedGroupMinimumSize = 4

    /// 形から、添字や隣やまとまりを引けるようにする。
    func rebuildIndices() {
        let nodes = scene.nodes
        indexByID = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        var neighbors = [[(index: Int, weight: Float)]](repeating: [], count: nodes.count)
        edgeWeights = [:]
        for edge in scene.edges {
            neighbors[edge.source].append((edge.target, edge.weight))
            neighbors[edge.target].append((edge.source, edge.weight))
            edgeWeights[Self.edgeKey(edge.source, edge.target), default: 0] += edge.weight
        }
        neighborIndices = neighbors.map { list in list.sorted { $0.weight > $1.weight }.map(\.index) }

        var groupIndex: [Int: Int] = [:]
        for node in nodes where groupIndex[node.group] == nil {
            groupIndex[node.group] = groupIndex.count
        }
        groupIndexByID = groupIndex
        groupSizes = [Int](repeating: 0, count: groupIndex.count)
        for node in nodes { groupSizes[groupIndex[node.group]!] += 1 }

        namedGroups = scene.groups.enumerated().compactMap { entry, group in
            guard let index = groupIndex[group.id], groupSizes[index] >= Self.namedGroupMinimumSize,
                !group.name.isEmpty
            else { return nil }
            return (index, entry)
        }
        let named = Set(namedGroups.map(\.group))
        info = nodes.map { node in
            let group = groupIndex[node.group]!
            let cloud: Float = named.contains(group) && groupSizes[group] >= Self.cloudMinimumSize ? 1 : 0
            return NodeInfo(node.radius, node.birth ?? -1, Float(group), cloud)
        }
        importanceOrder = nodes.indices.sorted { nodes[$0].radius > nodes[$1].radius }
        centroids = [SIMD4<Float>](repeating: .zero, count: max(groupIndex.count, 1))
    }

    static func edgeKey(_ first: Int, _ second: Int) -> Int64 {
        Int64(min(first, second)) << 32 | Int64(max(first, second))
    }

    /// まとまりの中心（寄せた後の座標の平均。時間の再生中は、現れた点だけ）。w は点の数。
    func updateCentroids() {
        var sums = [SIMD4<Float>](repeating: .zero, count: max(groupSizes.count, 1))
        for index in projected.indices {
            let group = Int(info[index].z)
            let weight = projected[index].look.w
            sums[group] += SIMD4(projected[index].world.xyz * weight, weight)
        }
        centroids = sums.map { sum in
            sum.w > 1e-3 ? SIMD4(sum.xyz / sum.w, sum.w) : .zero
        }
        renderer?.centroids.write(centroids)
    }

    /// 点の ID の添字。
    func index(of nodeID: Int?) -> Int? {
        nodeID.flatMap { indexByID[$0] }
    }

    /// まとまりの ID の点（添字）。
    func members(ofGroup groupID: Int) -> [Int] {
        scene.nodes.indices.filter { scene.nodes[$0].group == groupID }
    }
}
