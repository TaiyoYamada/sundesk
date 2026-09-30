//
//  ImagesViewModelTests.swift
//  ImagesFeatureTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import ImagesFeature
import SundeskDomain
import Testing

@MainActor
@Suite("ImagesViewModel")
struct ImagesViewModelTests {
    // MARK: - 生成

    @Test("生成すると進み具合を出し、できた画像を選ぶ")
    func generates() async {
        let generation = GenerationStub()
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        #expect(viewModel.modelID == "flux2-klein-4b")
        viewModel.prompt = "a cat on a desk"

        viewModel.generate()
        #expect(viewModel.isGenerating)
        #expect(viewModel.progress != nil)
        await finish(viewModel)

        #expect(viewModel.images.map(\.prompt) == ["a cat on a desk"])
        #expect(viewModel.selectedImage?.seed == 42)
        #expect(viewModel.progress == nil)
    }

    @Test("何枚か続けて作るときは、種を 1 ずつ変える")
    func generatesMany() async {
        let generation = GenerationStub()
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        viewModel.prompt = "山"
        viewModel.seed = 10
        viewModel.count = 3

        viewModel.generate()
        await finish(viewModel)

        #expect(await generation.requests.map(\.seed) == [10, 11, 12])
        #expect(viewModel.images.count == 3)
        #expect(viewModel.selection == [viewModel.images[0].id])
    }

    @Test("種が空なら、何枚でも毎回エンジンに任せる")
    func generatesManyWithRandomSeeds() async {
        let generation = GenerationStub()
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        viewModel.prompt = "海"
        viewModel.count = 2

        viewModel.generate()
        await finish(viewModel)

        #expect(await generation.requests.map(\.seed) == [nil, nil])
    }

    @Test("縦横比と長い辺から、幅と高さを決めて頼む")
    func requestsDimensions() async {
        let generation = GenerationStub()
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        viewModel.prompt = "街"
        viewModel.aspectRatio = .landscape16x9
        viewModel.size = 768

        #expect(viewModel.dimensions == ImageDimensions(width: 768, height: 432))
        viewModel.generate()
        await finish(viewModel)

        let request = await generation.requests.first
        #expect(request?.width == 768)
        #expect(request?.height == 432)
    }

    @Test("幅と高さは、どの組み合わせでも 16 の倍数で 256〜2048 に収まる")
    func dimensionsAreValid() {
        for ratio in ImageAspectRatio.allCases {
            for size in ImagesViewModel.sizes {
                let dimensions = ratio.dimensions(longSide: size)
                #expect(dimensions.width % 16 == 0 && dimensions.height % 16 == 0)
                #expect(ImageAspectRatio.sideRange.contains(dimensions.width))
                #expect(ImageAspectRatio.sideRange.contains(dimensions.height))
                #expect(max(dimensions.width, dimensions.height) == size)
            }
        }
        #expect(ImageAspectRatio.square.dimensions(longSide: 1024) == ImageDimensions(width: 1024, height: 1024))
        #expect(ImageAspectRatio.portrait9x16.dimensions(longSide: 512) == ImageDimensions(width: 288, height: 512))
        #expect(ImageAspectRatio.landscape3x2.dimensions(longSide: 1024) == ImageDimensions(width: 1024, height: 688))
        #expect(ImageAspectRatio.portrait3x4.dimensions(longSide: 1024) == ImageDimensions(width: 768, height: 1024))
    }

    @Test("止めると、残りの枚数は作らない")
    func cancels() async {
        let generation = GenerationStub(delay: .milliseconds(50))
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        viewModel.prompt = "森"
        viewModel.count = 5

        viewModel.generate()
        viewModel.cancel()
        await finish(viewModel)

        #expect(await generation.requests.count <= 1)
        #expect(!viewModel.isGenerating)
        #expect(viewModel.progress == nil)
    }

    @Test("プロンプトが空なら生成できない")
    func needsPrompt() {
        let viewModel = ImagesViewModel(generation: GenerationStub())
        viewModel.prompt = " "

        #expect(!viewModel.canGenerate)
    }

    // MARK: - 設定を使う

    @Test("同じ設定を入力に戻せる")
    func reusesSettings() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["前の画像"]))
        await viewModel.load()
        let id = viewModel.images[0].id

        viewModel.reuseSettings(of: id)

        #expect(viewModel.prompt == "前の画像")
        #expect(viewModel.seed == 0)
        #expect(viewModel.size == 512)
        #expect(viewModel.aspectRatio == .square)
    }

    @Test("横長の画像の設定を戻すと、縦横比も戻る")
    func reusesAspectRatio() async {
        let image = GenerationStub.image("横長", width: 1024, height: 576)
        let viewModel = ImagesViewModel(generation: GenerationStub(images: [image]))
        await viewModel.load()

        viewModel.reuseSettings(of: image.id)

        #expect(viewModel.aspectRatio == .landscape16x9)
        #expect(viewModel.size == 1024)
        #expect(viewModel.dimensions == ImageDimensions(width: 1024, height: 576))
    }

    @Test("種だけ変えてもう一度作る")
    func regeneratesWithNewSeed() async {
        let generation = GenerationStub(prompts: ["前の画像"])
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()

        viewModel.regenerate(from: viewModel.images[0].id)
        await finish(viewModel)

        let request = await generation.requests.first
        #expect(request?.prompt == "前の画像")
        #expect(request?.seed == nil)
    }

    @Test("これまでのプロンプトを、新しい順に重ならずに出す")
    func promptHistory() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(prompts: ["猫", "犬", "猫", "鳥"]))
        await viewModel.load()

        #expect(viewModel.promptHistory == ["猫", "犬", "鳥"])
    }

    private func finish(_ viewModel: ImagesViewModel) async {
        for _ in 0..<400 where viewModel.isGenerating {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
