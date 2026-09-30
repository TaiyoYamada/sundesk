//
//  GenerationStub.swift
//  ImagesFeatureTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// 画像生成の UseCase の代わり。頼まれた設定と消した画像を覚えておく。
actor GenerationStub: ImageGenerationUseCase {
    private var stored: [GeneratedImage]
    private(set) var requests: [ImageRequest] = []
    private(set) var deleted: [UUID] = []
    private let delay: Duration?

    init(prompts: [String] = [], delay: Duration? = nil) {
        stored = prompts.enumerated().map { index, prompt in
            Self.image(prompt, seed: index, createdAt: Date(timeIntervalSince1970: Double(1000 - index)))
        }
        self.delay = delay
    }

    init(images: [GeneratedImage], delay: Duration? = nil) {
        stored = images
        self.delay = delay
    }

    static func image(
        _ prompt: String, width: Int = 512, height: Int = 512, seed: Int = 7, path: String = "/a.png",
        createdAt: Date = .now
    ) -> GeneratedImage {
        GeneratedImage(
            id: UUID(), model: "z-image-turbo", prompt: prompt, width: width, height: height, steps: 9, seed: seed,
            path: path, seconds: 5, createdAt: createdAt)
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
            let task = Task {
                await self.record(request)
                if let delay = self.delay { try? await Task.sleep(for: delay) }
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                let image = GeneratedImage(
                    id: UUID(), model: request.model, prompt: request.prompt, width: request.width,
                    height: request.height, steps: request.steps, seed: request.seed ?? 42, path: "/new.png",
                    seconds: 3, createdAt: .now)
                continuation.yield(.progress(step: 1, total: 4))
                await self.add(image)
                continuation.yield(.done(image))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func record(_ request: ImageRequest) {
        requests.append(request)
    }

    private func add(_ image: GeneratedImage) {
        stored.insert(image, at: 0)
    }

    func images() async throws(LabError) -> [GeneratedImage] { stored }

    func delete(_ images: [GeneratedImage]) async throws(LabError) {
        deleted += images.map(\.id)
        let ids = Set(images.map(\.id))
        stored.removeAll { ids.contains($0.id) }
    }

    func setFavorite(_ images: [GeneratedImage], isFavorite: Bool) async throws(LabError) {
        let ids = Set(images.map(\.id))
        stored = stored.map { image in
            guard ids.contains(image.id) else { return image }
            return GeneratedImage(
                id: image.id, model: image.model, prompt: image.prompt, width: image.width, height: image.height,
                steps: image.steps, seed: image.seed, path: image.path, seconds: image.seconds,
                createdAt: image.createdAt, isFavorite: isFavorite)
        }
    }

    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
