//
//  ImagesGalleryTests.swift
//  ImagesFeatureTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import ImagesFeature
import SundeskDomain
import Testing

@MainActor
@Suite("ImagesViewModel（選ぶ、消す、見る）")
struct ImagesGalleryTests {
    // MARK: - 選ぶ

    @Test("Finder と同じく、⌘ で足し引き、⇧ で範囲を選ぶ")
    func selects() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2", "3", "4", "5"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)

        viewModel.select(ids[1])
        viewModel.select(ids[3], modifier: .extend)
        #expect(viewModel.selection == Set(ids[1...3]))

        // ⇧ を押したまま起点の手前を選ぶと、範囲を選び直す
        viewModel.select(ids[0], modifier: .extend)
        #expect(viewModel.selection == Set(ids[0...1]))

        // ⌘ で足してから ⇧ で広げると、⌘ で足したものは残る
        viewModel.select(ids[4], modifier: .toggle)
        viewModel.select(ids[5], modifier: .extend)
        #expect(viewModel.selection == Set([ids[0], ids[1], ids[4], ids[5]]))
        #expect(viewModel.orderedSelection == [ids[0], ids[1], ids[4], ids[5]])

        viewModel.select(ids[0], modifier: .toggle)
        #expect(!viewModel.isSelected(ids[0]))

        viewModel.select(ids[2])
        #expect(viewModel.selection == [ids[2]])
        #expect(viewModel.selectedImage?.id == ids[2])
    }

    @Test("⌘A ですべてを選び、何もないところで外す")
    func selectsAll() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["a", "b", "c"]))
        await viewModel.load()

        viewModel.selectAll()
        #expect(viewModel.selection.count == 3)
        #expect(viewModel.selectedImage == nil)
        #expect(viewModel.selectedImages.count == 3)

        viewModel.clearSelection()
        #expect(viewModel.selection.isEmpty)
    }

    @Test("矢印で選んでいる画像を動かし、⇧ で広げる")
    func movesSelection() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2", "3", "4", "5"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)

        viewModel.moveSelection(by: 1)
        #expect(viewModel.selection == [ids[0]])
        viewModel.moveSelection(by: 3)
        #expect(viewModel.selection == [ids[3]])
        viewModel.moveSelection(by: 1, extending: true)
        #expect(viewModel.selection == Set(ids[3...4]))
        viewModel.moveSelection(by: 10)
        #expect(viewModel.selection == [ids[5]])
        viewModel.moveSelection(by: -10)
        #expect(viewModel.selection == [ids[0]])
    }

    @Test("右クリックした画像が選択の中なら選択のすべて、外ならその 1 枚が相手")
    func contextTargets() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)
        viewModel.select(ids[0])
        viewModel.select(ids[1], modifier: .extend)

        #expect(viewModel.targets(for: ids[1]) == [ids[0], ids[1]])
        #expect(viewModel.targets(for: ids[2]) == [ids[2]])
    }

    @Test("プロンプトで絞り込むと、見えなくなった画像は選択から外す")
    func filters() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["red cat", "blue dog", "Red fox"]))
        await viewModel.load()
        viewModel.selectAll()

        viewModel.searchText = "red"

        #expect(viewModel.visibleImages.map(\.prompt) == ["red cat", "Red fox"])
        #expect(viewModel.selectedImages.map(\.prompt) == ["red cat", "Red fox"])
        #expect(viewModel.selection.count == 2)
    }

    // MARK: - お気に入り

    @Test("1 枚でも付いていなければすべてに付け、すべて付いていれば外す")
    func togglesFavorites() async {
        let generation = GenerationStub(prompts: ["a", "b", "c"])
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)
        await viewModel.toggleFavorite([ids[0]])
        #expect(viewModel.isFavorite([ids[0]]))

        await viewModel.toggleFavorite([ids[0], ids[1]])
        #expect(viewModel.isFavorite([ids[0], ids[1]]))

        viewModel.showsFavoritesOnly = true
        #expect(viewModel.visibleImages.map(\.id) == [ids[0], ids[1]])

        await viewModel.toggleFavorite([ids[0], ids[1]])
        #expect(viewModel.visibleImages.isEmpty)
    }

    // MARK: - 削除

    @Test("選んだ画像を尋ねてからまとめて消し、すぐ後ろの画像を選ぶ")
    func deletesSelection() async {
        let generation = GenerationStub(prompts: ["0", "1", "2", "3", "4"])
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)
        viewModel.select(ids[1])
        viewModel.select(ids[3], modifier: .extend)

        viewModel.requestDelete()
        #expect(viewModel.pendingDeletion == [ids[1], ids[2], ids[3]])
        #expect(viewModel.deletionTitle == "3 枚の画像を削除しますか？")
        await viewModel.delete(viewModel.pendingDeletion)

        #expect(await generation.deleted == [ids[1], ids[2], ids[3]])
        #expect(viewModel.images.map(\.prompt) == ["0", "4"])
        #expect(viewModel.selection == [ids[4]])
        #expect(viewModel.pendingDeletion.isEmpty)
    }

    @Test("最後の画像を消すと、すぐ前の画像を選ぶ")
    func deletesLast() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)

        viewModel.requestDelete([ids[2]])
        #expect(viewModel.deletionTitle == "この画像を削除しますか？")
        await viewModel.delete(viewModel.pendingDeletion)

        #expect(viewModel.selection == [ids[1]])
    }

    @Test("やめれば何も消さない")
    func cancelsDeletion() async {
        let generation = GenerationStub(prompts: ["0", "1"])
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        viewModel.selectAll()

        viewModel.requestDelete()
        viewModel.cancelDeletion()

        #expect(viewModel.pendingDeletion.isEmpty)
        #expect(await generation.deleted.isEmpty)
        #expect(viewModel.images.count == 2)
    }

    @Test("絞り込みで見えない画像は、⌘A のあとでも消さない")
    func deletesOnlyVisible() async {
        let generation = GenerationStub(prompts: ["cat", "dog", "cat 2"])
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        viewModel.searchText = "cat"
        viewModel.selectAll()

        viewModel.requestDelete()
        await viewModel.delete(viewModel.pendingDeletion)

        #expect(viewModel.images.map(\.prompt) == ["dog"])
    }

    // MARK: - 大きく見る、比べる

    @Test("ビューアで前後に移り、端で止まる")
    func viewer() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)
        viewModel.select(ids[1])

        viewModel.openViewer()
        #expect(viewModel.viewerImage?.id == ids[1])
        #expect(viewModel.viewerPosition == "2 / 3")

        viewModel.showAdjacent(1)
        #expect(viewModel.viewerImage?.id == ids[2])
        #expect(viewModel.selection == [ids[2]])
        #expect(!viewModel.canShowNext)
        viewModel.showAdjacent(1)
        #expect(viewModel.viewerImage?.id == ids[2])

        viewModel.showAdjacent(-2)
        #expect(viewModel.viewerImage?.id == ids[0])
        #expect(!viewModel.canShowPrevious)

        viewModel.closeViewer()
        #expect(viewModel.viewerImage == nil)
        #expect(viewModel.selection == [ids[0]])
    }

    @Test("ビューアで見ている画像を消すと、次の画像を見る")
    func deletesInViewer() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)
        viewModel.openViewer(ids[1])

        viewModel.requestDelete([ids[1]])
        await viewModel.delete(viewModel.pendingDeletion)

        #expect(viewModel.viewerImage?.id == ids[2])
    }

    @Test("2〜4 枚を選べば並べて比べられる")
    func compares() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["0", "1", "2", "3", "4"]))
        await viewModel.load()
        let ids = viewModel.visibleImages.map(\.id)

        viewModel.select(ids[0])
        #expect(!viewModel.canCompare)
        viewModel.select(ids[2], modifier: .toggle)
        #expect(viewModel.canCompare)
        viewModel.compareSelection()
        #expect(viewModel.comparedImages.map(\.id) == [ids[0], ids[2]])
        viewModel.closeComparison()
        #expect(viewModel.comparedImages.isEmpty)

        viewModel.selectAll()
        #expect(!viewModel.canCompare)
    }

    // MARK: - 書き出し

    @Test("書き出すファイル名は、プロンプトの頭と種")
    func suggestsFileName() async {
        let image = GenerationStub.image("A cat, on the desk!", seed: 42)
        let viewModel = ImagesViewModel(generation: GenerationStub(images: [image]))
        await viewModel.load()

        #expect(viewModel.suggestedFileName(for: image.id) == "a-cat-on-the-desk-42.png")
    }

    @Test("何枚かをフォルダに書き出し、同じ名前は番号で分ける")
    func exports() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.png")
        try Data([1, 2, 3]).write(to: source)
        let first = GenerationStub.image("cat", seed: 1, path: source.path)
        let second = GenerationStub.image("cat", seed: 1, path: source.path)
        let viewModel = ImagesViewModel(generation: GenerationStub(images: [first, second]))
        await viewModel.load()
        let output = directory.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let count = viewModel.export([first.id, second.id], toDirectory: output)

        #expect(count == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        #expect(names == ["cat-1 2.png", "cat-1.png"])
    }
}
