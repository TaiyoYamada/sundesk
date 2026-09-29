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
    @Test("生成すると進み具合を出し、できた画像を選ぶ")
    func generates() async {
        let generation = GenerationStub()
        let viewModel = ImagesViewModel(generation: generation)
        await viewModel.load()
        #expect(viewModel.modelID == "flux2-klein-4b")
        viewModel.prompt = "a cat on a desk"

        viewModel.generate()
        #expect(viewModel.isGenerating)
        for _ in 0..<200 where viewModel.isGenerating {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.images.map(\.prompt) == ["a cat on a desk"])
        #expect(viewModel.selectedImage?.seed == 42)
        #expect(viewModel.progress == nil)
    }

    @Test("同じ設定を入力に戻せる")
    func reusesSettings() async {
        let viewModel = ImagesViewModel(generation: GenerationStub(existing: true))
        await viewModel.load()
        let id = viewModel.images[0].id

        viewModel.reuseSettings(of: id)

        #expect(viewModel.prompt == "前の画像")
        #expect(viewModel.seed == 7)
        #expect(viewModel.size == 512)
    }

    @Test("プロンプトが空なら生成できない")
    func needsPrompt() {
        let viewModel = ImagesViewModel(generation: GenerationStub())
        viewModel.prompt = " "

        #expect(!viewModel.canGenerate)
    }
}

private actor GenerationStub: ImageGenerationUseCase {
    private var stored: [GeneratedImage]

    init(existing: Bool = false) {
        stored =
            existing
            ? [
                GeneratedImage(
                    id: UUID(), model: "z-image-turbo", prompt: "前の画像", width: 512, height: 512, steps: 9, seed: 7,
                    path: "/a.png", seconds: 5, createdAt: .now)
            ] : []
    }

    func models() async throws(LabError) -> [ImageModelOption] {
        [
            ImageModelOption(
                id: "flux2-klein-4b", name: "FLUX.2 klein", repository: "r", isDownloaded: false, defaultSteps: 4,
                defaultSize: 1024)
        ]
    }

    nonisolated func generate(_ request: ImageRequest) -> AsyncThrowingStream<ImageGenerationEvent, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                let image = GeneratedImage(
                    id: UUID(), model: request.model, prompt: request.prompt, width: request.width,
                    height: request.height,
                    steps: request.steps, seed: 42, path: "/new.png", seconds: 3, createdAt: .now)
                continuation.yield(.progress(step: 1, total: 4))
                await self.add(image)
                continuation.yield(.done(image))
                continuation.finish()
            }
        }
    }

    private func add(_ image: GeneratedImage) {
        stored.insert(image, at: 0)
    }

    func images() async throws(LabError) -> [GeneratedImage] { stored }
    func delete(_ image: GeneratedImage) async throws(LabError) { stored.removeAll { $0.id == image.id } }
    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
