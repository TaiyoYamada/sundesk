//
//  ImagesViewModel.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 画像生成。プロンプトと設定から生成し、できた画像を一覧して、見る、選ぶ、消す、書き出す。
///
/// 選ぶ、見る、消すなどの操作は `ImagesViewModel+Gallery.swift` と `ImagesViewModel+Actions.swift` にある。
@MainActor
@Observable
public final class ImagesViewModel {
    // MARK: - 入力

    public private(set) var models: [ImageModelItem] = []
    public var modelID = "z-image-turbo"
    /// 一度モデルを選んだら、開き直しても勝手に変えない。
    @ObservationIgnored private var hasChosenModel = false
    public var prompt = ""
    public var aspectRatio: ImageAspectRatio = .square
    /// 長い辺の長さ。
    public var size = 1024
    public static let sizes = [512, 768, 1024, 1536]
    /// nil ならモデルの既定。
    public var steps: Int?
    /// nil なら毎回変える。何枚か作るときは、1 枚ごとに 1 ずつ足す。
    public var seed: Int?
    /// 続けて作る枚数。
    public var count = 1
    public static let counts = 1...8

    public var dimensions: ImageDimensions { aspectRatio.dimensions(longSide: size) }

    // MARK: - 画像

    /// すべての画像（新しい順）。
    public private(set) var images: [ImageItem] = []
    /// 絞り込んだあとの画像。選ぶ、移るなどの操作は、これを順に使う。
    public internal(set) var visibleImages: [ImageItem] = []
    /// プロンプトで絞り込む。
    public var searchText = "" {
        didSet { applyFilter() }
    }
    /// お気に入りだけを見る。
    public var showsFavoritesOnly = false {
        didSet { applyFilter() }
    }
    /// これまでのプロンプト（新しい順、重なりなし）。
    public private(set) var promptHistory: [String] = []

    // MARK: - 選択、ビューア、削除

    public internal(set) var selection: Set<UUID> = []
    /// 最後に選んだ画像。Space で開き、矢印で動くときの起点。
    public internal(set) var focusedImageID: UUID?
    /// ⇧ で範囲を選ぶときの起点と、そのときまでに選んでいたもの。
    @ObservationIgnored var anchorID: UUID?
    @ObservationIgnored var baseSelection: Set<UUID> = []
    /// 大きく見ている画像。nil なら閉じている。
    public internal(set) var viewerImageID: UUID?
    /// 並べて比べている画像。空なら比べていない。
    public internal(set) var comparedImageIDs: [UUID] = []
    /// 消してよいかを尋ねている画像。
    public internal(set) var pendingDeletion: [UUID] = []

    // MARK: - 生成

    public private(set) var progress: ProgressItem?
    public var errorMessage: String?
    /// 生成している途中か。`task` は観測しないので、別に持つ。
    public private(set) var isGenerating = false
    public var canGenerate: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating }

    @ObservationIgnored let generation: any ImageGenerationUseCase
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var records: [UUID: GeneratedImage] = [:]

    /// - Parameter now: 今の時刻（テストで差し替える）。
    public init(generation: any ImageGenerationUseCase, now: @escaping @Sendable () -> Date = { .now }) {
        self.generation = generation
        self.now = now
    }

    public func load() async {
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
        await reloadImages()
    }

    public func observe() async {
        for await _ in generation.changes() {
            await reloadImages()
        }
    }

    func reloadImages() async {
        let loaded = (try? await generation.images()) ?? []
        records = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(models.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        images = loaded.map { ImageItem($0, modelName: names[$0.model]) }
        var seen = Set<String>()
        promptHistory = loaded.map(\.prompt).filter { seen.insert($0).inserted }
        applyFilter()
    }

    /// 絞り込みを当て直し、見えなくなった画像を選択から外す（見えないものを消さないように）。
    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleImages = images.filter { image in
            (!showsFavoritesOnly || image.isFavorite)
                && (query.isEmpty || image.prompt.localizedStandardContains(query))
        }
        let visible = Set(visibleImages.map(\.id))
        if !selection.isSubset(of: visible) { selection.formIntersection(visible) }
        if let focusedImageID, !visible.contains(focusedImageID) { self.focusedImageID = nil }
        if let anchorID, !visible.contains(anchorID) { self.anchorID = nil }
        let existing = Set(images.map(\.id))
        if let viewerImageID, !existing.contains(viewerImageID) { self.viewerImageID = nil }
        comparedImageIDs.removeAll { !existing.contains($0) }
        if comparedImageIDs.count < 2 { comparedImageIDs = [] }
    }

    // MARK: - 生成

    public func generate() {
        guard canGenerate else { return }
        errorMessage = nil
        let dimensions = dimensions
        let base = ImageRequest(
            model: modelID, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), width: dimensions.width,
            height: dimensions.height, steps: steps, seed: seed)
        let requests = (0..<min(max(count, 1), Self.counts.upperBound)).map { index in
            var request = base
            request.seed = base.seed.map { ($0 + index) % (1 << 32) }
            return request
        }
        let startedAt = now()
        let previous = previousSeconds(for: base)
        progress = ProgressItem(
            title: "準備しています", detail: batchLabel(0, requests.count), fraction: nil, startedAt: startedAt,
            estimatedEnd: GenerationEstimator(count: requests.count, startedAt: startedAt, previousSeconds: previous)
                .estimatedEnd(now: startedAt),
            width: dimensions.width, height: dimensions.height)
        isGenerating = true
        task = Task {
            var estimator = GenerationEstimator(count: requests.count, startedAt: startedAt, previousSeconds: previous)
            do {
                for (index, request) in requests.enumerated() {
                    try Task.checkCancellation()
                    estimator.startImage(index, at: now())
                    try await run(request, estimator: &estimator)
                }
            } catch is CancellationError {
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            progress = nil
            task = nil
            isGenerating = false
        }
    }

    /// 1 枚を作る。
    private func run(_ request: ImageRequest, estimator: inout GenerationEstimator) async throws {
        let batch = batchLabel(estimator.index, estimator.count)
        let base = ProgressItem(
            title: "準備しています", detail: batch, fraction: estimator.fraction(step: 0, of: 1), startedAt: now(),
            estimatedEnd: estimator.estimatedEnd(now: now()), width: request.width, height: request.height)
        progress = update(progress ?? base, detail: batch)
        for try await event in generation.generate(request) {
            try Task.checkCancellation()
            switch event {
            case .loading:
                estimator.loading()
                progress = update(
                    progress ?? base, title: "モデルを読み込んでいます（初回はダウンロードに時間がかかります）",
                    estimatedEnd: .some(nil))
            case .progress(let step, let total):
                let date = now()
                estimator.step(step, of: total, at: date)
                progress = update(
                    progress ?? base, title: "生成しています",
                    detail: [batch, "ステップ \(step)/\(total)"].compactMap(\.self).joined(separator: " · "),
                    fraction: estimator.fraction(step: step, of: total),
                    estimatedEnd: estimator.estimatedEnd(now: date, step: step))
            case .done(let image):
                await reloadImages()
                // できた画像を選ぶ（絞り込みで見えないときは、選ばない）
                if visibleImages.contains(where: { $0.id == image.id }) {
                    select(image.id)
                }
            }
        }
    }

    private func update(
        _ item: ProgressItem, title: String? = nil, detail: String?? = nil, fraction: Double?? = nil,
        estimatedEnd: Date?? = nil
    ) -> ProgressItem {
        ProgressItem(
            title: title ?? item.title, detail: detail ?? item.detail, fraction: fraction ?? item.fraction,
            startedAt: item.startedAt, estimatedEnd: estimatedEnd ?? item.estimatedEnd, width: item.width,
            height: item.height)
    }

    private func batchLabel(_ index: Int, _ count: Int) -> String? {
        count > 1 ? "\(index + 1)/\(count) 枚目" : nil
    }

    /// 前に同じモデル、大きさ、ステップで作ったときの時間。
    private func previousSeconds(for request: ImageRequest) -> Double? {
        records.values
            .filter {
                $0.model == request.model && $0.width == request.width && $0.height == request.height
                    && $0.steps == request.steps
            }
            .max { $0.createdAt < $1.createdAt }?
            .seconds
    }

    public func cancel() {
        task?.cancel()
    }
}
