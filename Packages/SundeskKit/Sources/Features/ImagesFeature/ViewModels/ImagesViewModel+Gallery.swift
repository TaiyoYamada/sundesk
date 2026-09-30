//
//  ImagesViewModel+Gallery.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

// MARK: - 選ぶ

extension ImagesViewModel {
    /// 1 枚だけ選んでいるときの、その画像。
    public var selectedImage: ImageItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return image(for: id)
    }

    /// 選んでいる画像（ギャラリーの順）。
    public var selectedImages: [ImageItem] {
        visibleImages.filter { selection.contains($0.id) }
    }

    /// 選んでいる画像の ID（ギャラリーの順）。
    public var orderedSelection: [UUID] {
        selectedImages.map(\.id)
    }

    public func image(for id: UUID) -> ImageItem? {
        images.first { $0.id == id }
    }

    public func isSelected(_ id: UUID) -> Bool {
        selection.contains(id)
    }

    /// クリックで選ぶ。Finder と同じく、⌘ で足し引き、⇧ で起点からの範囲を選ぶ。
    public func select(_ id: UUID, modifier: SelectionModifier = .none) {
        switch modifier {
        case .none:
            selection = [id]
            anchorID = id
            baseSelection = []
        case .toggle:
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
            anchorID = id
            baseSelection = selection
        case .extend:
            guard let anchorID, let range = range(from: anchorID, to: id) else {
                select(id)
                return
            }
            selection = baseSelection.union(range)
        }
        focusedImageID = id
    }

    /// ⌘A: 見えている画像をすべて選ぶ。
    public func selectAll() {
        selection = Set(visibleImages.map(\.id))
        baseSelection = []
        if anchorID == nil { anchorID = visibleImages.first?.id }
        if focusedImageID == nil { focusedImageID = visibleImages.first?.id }
    }

    /// 何もないところをクリックしたとき。
    public func clearSelection() {
        selection = []
        baseSelection = []
    }

    /// 矢印で、選んでいる画像を動かす。`offset` は左右なら ±1、上下なら ±列の数。
    /// - Parameter extending: ⇧ を押しているなら、起点からの範囲を選ぶ。
    public func moveSelection(by offset: Int, extending: Bool = false) {
        guard !visibleImages.isEmpty else { return }
        let target: Int
        if let focusedImageID, let index = visibleImages.firstIndex(where: { $0.id == focusedImageID }) {
            target = min(max(index + offset, 0), visibleImages.count - 1)
        } else {
            target = offset >= 0 ? 0 : visibleImages.count - 1
        }
        select(visibleImages[target].id, modifier: extending ? .extend : .none)
    }

    /// 右クリックのメニューが相手にする画像。選んでいる画像を右クリックしたら選択のすべて、そうでなければその 1 枚。
    public func targets(for id: UUID) -> [UUID] {
        selection.contains(id) ? orderedSelection : [id]
    }

    private func range(from start: UUID, to end: UUID) -> Set<UUID>? {
        guard let first = visibleImages.firstIndex(where: { $0.id == start }),
            let last = visibleImages.firstIndex(where: { $0.id == end })
        else { return nil }
        return Set(visibleImages[min(first, last)...max(first, last)].map(\.id))
    }
}

// MARK: - 大きく見る

extension ImagesViewModel {
    public var viewerImage: ImageItem? {
        viewerImageID.flatMap(image(for:))
    }

    /// 「3 / 24」のような、今の位置。
    public var viewerPosition: String? {
        guard let viewerImageID, let index = visibleImages.firstIndex(where: { $0.id == viewerImageID }) else {
            return nil
        }
        return "\(index + 1) / \(visibleImages.count)"
    }

    public var canShowPrevious: Bool { adjacentImageID(-1) != nil }
    public var canShowNext: Bool { adjacentImageID(1) != nil }

    /// 大きく開く。`id` がなければ、最後に選んだ画像を開く。
    public func openViewer(_ id: UUID? = nil) {
        guard
            let target = id ?? focusedImageID.flatMap({ selection.contains($0) ? $0 : nil })
                ?? orderedSelection.first ?? visibleImages.first?.id
        else { return }
        viewerImageID = target
        if !selection.contains(target) || selection.count == 1 { select(target) }
        focusedImageID = target
    }

    public func closeViewer() {
        viewerImageID = nil
    }

    /// 前後の画像へ移る（ギャラリーの順。端で止まる）。
    public func showAdjacent(_ offset: Int) {
        guard let next = adjacentImageID(offset) else { return }
        viewerImageID = next
        select(next)
    }

    private func adjacentImageID(_ offset: Int) -> UUID? {
        guard let viewerImageID, let index = visibleImages.firstIndex(where: { $0.id == viewerImageID }) else {
            return nil
        }
        let target = index + offset
        return visibleImages.indices.contains(target) ? visibleImages[target].id : nil
    }
}

// MARK: - 並べて比べる

extension ImagesViewModel {
    public static let comparableCount = 2...4

    public var canCompare: Bool { Self.comparableCount.contains(selection.count) }

    public var comparedImages: [ImageItem] {
        comparedImageIDs.compactMap(image(for:))
    }

    /// 選んでいる 2〜4 枚を並べて比べる。
    public func compareSelection() {
        guard canCompare else { return }
        viewerImageID = nil
        comparedImageIDs = orderedSelection
    }

    public func closeComparison() {
        comparedImageIDs = []
    }
}
