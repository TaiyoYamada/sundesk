//
//  ImagesViewModel+Actions.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

// MARK: - 設定を使う

extension ImagesViewModel {
    /// 選んだ画像と同じ設定を、入力に戻す（同じ種でもう一度、など）。
    public func reuseSettings(of id: UUID) {
        guard let image = records[id] else { return }
        prompt = image.prompt
        modelID = image.model
        aspectRatio = ImageAspectRatio.closest(width: image.width, height: image.height)
        let longSide = max(image.width, image.height)
        size = Self.sizes.min { abs($0 - longSide) < abs($1 - longSide) } ?? longSide
        steps = image.steps
        seed = image.seed
    }

    /// 選んだ画像の設定で、もう一度作る。
    /// - Parameter keepingSeed: false なら種だけ変える（ほかの設定はそのまま）。
    public func regenerate(from id: UUID, keepingSeed: Bool = false) {
        guard records[id] != nil, !isGenerating else { return }
        reuseSettings(of: id)
        if !keepingSeed { seed = nil }
        generate()
    }
}

// MARK: - お気に入り

extension ImagesViewModel {
    /// すべてお気に入りか。
    public func isFavorite(_ ids: [UUID]) -> Bool {
        !ids.isEmpty && ids.allSatisfy { records[$0]?.isFavorite == true }
    }

    /// お気に入りを付け外しする。1 枚でも付いていなければ、すべてに付ける（写真アプリと同じ）。
    /// - Parameter ids: nil なら、いま選んでいる画像。
    public func toggleFavorite(_ ids: [UUID]? = nil) async {
        let targets = (ids ?? orderedSelection).compactMap { records[$0] }
        guard !targets.isEmpty else { return }
        do {
            try await generation.setFavorite(targets, isFavorite: !isFavorite(targets.map(\.id)))
            await reloadImages()
        } catch {
            errorMessage = error.message
        }
    }
}

// MARK: - 削除

extension ImagesViewModel {
    /// 消してよいかを尋ねる。
    /// - Parameter ids: nil なら、いま選んでいる画像。
    public func requestDelete(_ ids: [UUID]? = nil) {
        let targets = (ids ?? orderedSelection).filter { records[$0] != nil }
        guard !targets.isEmpty else { return }
        pendingDeletion = targets
    }

    public var deletionTitle: String {
        pendingDeletion.count == 1 ? "この画像を削除しますか？" : "\(pendingDeletion.count) 枚の画像を削除しますか？"
    }

    public func cancelDeletion() {
        pendingDeletion = []
    }

    /// 尋ねていた画像を消す。
    public func confirmDeletion() async {
        let ids = pendingDeletion
        pendingDeletion = []
        await delete(ids)
    }

    /// 画像を、ファイルと記録ごと消す。消したあとは、すぐ後ろの画像を選ぶ。
    public func delete(_ ids: [UUID]) async {
        let targets = ids.compactMap { records[$0] }
        guard !targets.isEmpty else { return }
        let deleted = Set(ids)
        let next = imageAfterDeleting(deleted)
        let viewing = viewerImageID
        do {
            try await generation.delete(targets)
        } catch {
            errorMessage = error.message
        }
        await reloadImages()
        let remaining = Set(images.map(\.id))
        let removed = deleted.subtracting(remaining)
        guard !removed.isEmpty else { return }
        if let next, remaining.contains(next) {
            select(next)
        } else {
            clearSelection()
            focusedImageID = nil
        }
        // ビューアで見ていた画像を消したら、次の画像を見る（なければ閉じる）
        if let viewing, removed.contains(viewing) {
            viewerImageID = next.flatMap { remaining.contains($0) ? $0 : nil }
        }
    }

    /// 消すものの最後のすぐ後ろ（なければすぐ前）の、残る画像。
    private func imageAfterDeleting(_ deleted: Set<UUID>) -> UUID? {
        let order = visibleImages.map(\.id)
        guard let last = order.lastIndex(where: { deleted.contains($0) }) else { return nil }
        if let after = order[(last + 1)...].first(where: { !deleted.contains($0) }) { return after }
        return order[..<last].last { !deleted.contains($0) }
    }
}

// MARK: - 書き出し

extension ImagesViewModel {
    public func urls(for ids: [UUID]) -> [URL] {
        ids.compactMap { image(for: $0)?.url }
    }

    /// 書き出すときのファイル名（プロンプトの頭と種）。
    public func suggestedFileName(for id: UUID) -> String {
        guard let image = records[id] else { return "image.png" }
        let words = image.prompt
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var name = ""
        for word in words {
            let next = name.isEmpty ? word : "\(name)-\(word)"
            if next.count > 40 { break }
            name = next
        }
        return "\(name.isEmpty ? "image" : name.lowercased())-\(image.seed).png"
    }

    /// 1 枚を、選んだ場所に書き出す。
    public func export(_ id: UUID, to destination: URL) {
        guard let image = image(for: id) else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: image.url, to: destination)
        } catch {
            errorMessage = "書き出せませんでした: \(error.localizedDescription)"
        }
    }

    /// 何枚かを、選んだフォルダに書き出す。同じ名前があれば、番号を付けて分ける。
    /// - Returns: 書き出した枚数。
    @discardableResult
    public func export(_ ids: [UUID], toDirectory directory: URL) -> Int {
        var exported = 0
        for id in ids {
            guard let image = image(for: id) else { continue }
            let destination = uniqueURL(in: directory, name: suggestedFileName(for: id))
            do {
                try FileManager.default.copyItem(at: image.url, to: destination)
                exported += 1
            } catch {
                errorMessage = "書き出せませんでした: \(error.localizedDescription)"
            }
        }
        return exported
    }

    private func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) \(number).\(pathExtension)")
            number += 1
        }
        return candidate
    }
}
