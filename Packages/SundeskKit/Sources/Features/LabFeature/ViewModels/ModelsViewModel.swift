//
//  ModelsViewModel.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 手元のモデルの管理。Hugging Face からの取り込み、削除、メモリからの取り外し。
@MainActor
@Observable
public final class ModelsViewModel {
    public private(set) var models: [LocalModelItem] = []
    public private(set) var loaded: LoadedModelsItem?
    public var downloadID = ""
    public private(set) var download: DownloadItem?
    public private(set) var isLoading = false
    public var errorMessage: String?

    /// 取り込む候補（16GB で動く大きさのもの）。
    public static let suggestions: [SuggestedModel] = [
        SuggestedModel(id: "mlx-community/Qwen3-0.6B-4bit", note: "実験室で試す、いちばん小さな LLM（約 0.4GB）"),
        SuggestedModel(id: "mlx-community/Qwen3-1.7B-4bit", note: "LoRA を試しやすい大きさの LLM（約 1GB）"),
        SuggestedModel(id: ChatModelOption.defaultMLXID, note: "チャットの既定の LLM（約 2.3GB）"),
        SuggestedModel(id: "cl-nagoya/ruri-v3-130m", note: "検索に使う日本語の埋め込みモデル（約 0.5GB）"),
    ]

    @ObservationIgnored private let management: any ModelManagementUseCase
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    public init(management: any ModelManagementUseCase) {
        self.management = management
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            models = try await management.localModels().map(LocalModelItem.init)
            loaded = LoadedModelsItem(try await management.loadedModels())
        } catch {
            errorMessage = error.message
        }
    }

    public func startDownload(_ id: String? = nil) {
        let id = (id ?? downloadID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, download == nil else { return }
        download = DownloadItem(id: id, fraction: nil, detail: "準備しています")
        let stream = management.download(id)
        downloadTask = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let done, let total):
                        let detail =
                            ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
                            + (total.map { " / " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                                ?? "")
                        download = DownloadItem(
                            id: id, fraction: total.map { $0 > 0 ? Double(done) / Double($0) : 0 }, detail: detail)
                    case .done:
                        download = nil
                    }
                }
            } catch is CancellationError {
            } catch let error as LabError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            download = nil
            downloadTask = nil
            downloadID = ""
            await load()
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    public func delete(_ id: String) async {
        do {
            try await management.delete(id)
        } catch {
            errorMessage = error.message
        }
        await load()
    }

    /// メモリから外す（nil ならすべて）。
    public func unloadAll() async {
        do {
            try await management.unload(nil)
        } catch {
            errorMessage = error.message
        }
        await load()
    }
}

public struct LocalModelItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let size: String
    public let path: String

    init(_ model: LocalModel) {
        id = model.id
        kind =
            switch model.kind {
            case .llm: "LLM"
            case .embedding: "埋め込み"
            case .image: "画像生成"
            case .other: "その他"
            }
        size = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
        path = model.path
    }
}

public struct LoadedModelsItem: Hashable, Sendable {
    public let lines: [String]

    init(_ loaded: LoadedModels) {
        var lines: [String] = []
        if let llm = loaded.llm {
            lines.append("LLM: \(llm)" + (loaded.adapter.map { "（LoRA: \(($0 as NSString).lastPathComponent)）" } ?? ""))
        }
        if let image = loaded.image { lines.append("画像生成: \(image)") }
        if let embedding = loaded.embedding { lines.append("埋め込み: \(embedding)") }
        self.lines = lines
    }
}

public struct DownloadItem: Hashable, Sendable {
    public let id: String
    public let fraction: Double?
    public let detail: String
}

public struct SuggestedModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let note: String
}
