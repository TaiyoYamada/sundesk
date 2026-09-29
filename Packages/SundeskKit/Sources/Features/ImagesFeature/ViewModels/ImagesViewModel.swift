//
//  ImagesViewModel.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 画像生成。プロンプトと設定から生成し、履歴を一覧する。
@MainActor
@Observable
public final class ImagesViewModel {
    public private(set) var models: [ImageModelItem] = []
    public var modelID = "z-image-turbo"
    /// 一度モデルを選んだら、開き直しても勝手に変えない。
    @ObservationIgnored private var hasChosenModel = false
    public var prompt = ""
    public var size = 1024
    public static let sizes = [512, 768, 1024]
    /// nil ならモデルの既定。
    public var steps: Int?
    /// nil なら毎回変える。
    public var seed: Int?
    public private(set) var images: [ImageItem] = []
    public var selectedImageID: UUID?
    public private(set) var progress: ProgressItem?
    public var errorMessage: String?

    public var isGenerating: Bool { task != nil }
    public var canGenerate: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating }
    public var selectedImage: ImageItem? { images.first { $0.id == selectedImageID } }

    @ObservationIgnored private let generation: any ImageGenerationUseCase
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var records: [UUID: GeneratedImage] = [:]

    public init(generation: any ImageGenerationUseCase) {
        self.generation = generation
    }

    public func load() async {
        await reloadImages()
        do {
            models = try await generation.models().map(ImageModelItem.init)
            let current = models.first { $0.id == modelID }
            // 初めて開いたときは、ダウンロード済みのモデルを選んでおく（何 GB も落とさずにすぐ試せる）
            if !hasChosenModel, current?.isDownloaded != true, let downloaded = models.first(where: \.isDownloaded) {
                modelID = downloaded.id
            } else if current == nil, let first = models.first {
                modelID = first.id
            }
            hasChosenModel = true
        } catch {
            errorMessage = error.message
        }
    }

    public func observe() async {
        for await _ in generation.changes() {
            await reloadImages()
        }
    }

    private func reloadImages() async {
        let loaded = (try? await generation.images()) ?? []
        records = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        images = loaded.map(ImageItem.init)
    }

    public func generate() {
        guard canGenerate else { return }
        errorMessage = nil
        progress = ProgressItem(title: "準備しています", fraction: nil)
        let request = ImageRequest(
            model: modelID, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), width: size, height: size,
            steps: steps, seed: seed)
        let stream = generation.generate(request)
        task = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .loading:
                        progress = ProgressItem(title: "モデルを読み込んでいます（初回はダウンロードに時間がかかります）", fraction: nil)
                    case .progress(let step, let total):
                        progress = ProgressItem(
                            title: "生成しています（\(step)/\(total)）", fraction: total > 0 ? Double(step) / Double(total) : nil
                        )
                    case .done(let image):
                        await reloadImages()
                        selectedImageID = image.id
                    }
                }
            } catch is CancellationError {
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            progress = nil
            task = nil
        }
    }

    public func cancel() {
        task?.cancel()
    }

    /// 選んだ画像と同じ設定を、入力に戻す（同じ種でもう一度、など）。
    public func reuseSettings(of id: UUID) {
        guard let image = records[id] else { return }
        prompt = image.prompt
        modelID = image.model
        size = image.width
        steps = image.steps
        seed = image.seed
    }

    public func delete(_ id: UUID) async {
        guard let image = records[id] else { return }
        do {
            try await generation.delete(image)
            if selectedImageID == id { selectedImageID = nil }
        } catch {
            errorMessage = error.message
        }
    }
}

public struct ImageModelItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let isDownloaded: Bool

    init(_ option: ImageModelOption) {
        id = option.id
        name = option.name
        isDownloaded = option.isDownloaded
        detail = option.isDownloaded ? "\(option.defaultSteps) ステップ" : "最初に使うときにダウンロードします"
    }
}

public struct ImageItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let prompt: String
    public let model: String
    public let size: String
    public let seed: Int
    public let steps: String
    public let seconds: String
    public let date: String

    init(_ image: GeneratedImage) {
        id = image.id
        url = URL(filePath: image.path)
        prompt = image.prompt
        model = image.model
        size = "\(image.width) × \(image.height)"
        seed = image.seed
        steps = image.steps.map { "\($0)" } ?? "既定"
        seconds = String(format: "%.1f 秒", image.seconds)
        date = image.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

public struct ProgressItem: Hashable, Sendable {
    public let title: String
    public let fraction: Double?
}
