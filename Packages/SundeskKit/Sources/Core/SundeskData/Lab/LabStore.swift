//
//  LabStore.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskDomain
import SwiftData

/// 実験室の記録のスキーマ（Vault に関係ないので、アプリ全体で 1 つ）。
public enum LabSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ExperimentRecord.self, AdapterRecord.self, GeneratedImageRecord.self]
    }

    @Model
    public final class ExperimentRecord {
        #Unique<ExperimentRecord>([\.experimentID])

        public var experimentID: UUID
        public var kind: String
        public var model: String
        public var prompt: String
        /// 設定（JSON）。
        public var parameters: Data
        public var summary: String
        public var createdAt: Date

        public init(
            experimentID: UUID, kind: String, model: String, prompt: String, parameters: Data, summary: String,
            createdAt: Date
        ) {
            self.experimentID = experimentID
            self.kind = kind
            self.model = model
            self.prompt = prompt
            self.parameters = parameters
            self.summary = summary
            self.createdAt = createdAt
        }
    }

    @Model
    public final class AdapterRecord {
        #Unique<AdapterRecord>([\.adapterID])

        public var adapterID: UUID
        public var name: String
        public var model: String
        public var path: String
        /// 学習の設定（JSON）。
        public var settings: Data
        public var source: String
        public var finalLoss: Double?
        public var createdAt: Date

        public init(
            adapterID: UUID, name: String, model: String, path: String, settings: Data, source: String,
            finalLoss: Double?, createdAt: Date
        ) {
            self.adapterID = adapterID
            self.name = name
            self.model = model
            self.path = path
            self.settings = settings
            self.source = source
            self.finalLoss = finalLoss
            self.createdAt = createdAt
        }
    }

    @Model
    public final class GeneratedImageRecord {
        #Unique<GeneratedImageRecord>([\.imageID])

        public var imageID: UUID
        public var model: String
        public var prompt: String
        public var width: Int
        public var height: Int
        public var steps: Int?
        public var seed: Int
        public var path: String
        public var seconds: Double
        public var createdAt: Date

        public init(
            imageID: UUID, model: String, prompt: String, width: Int, height: Int, steps: Int?, seed: Int, path: String,
            seconds: Double, createdAt: Date
        ) {
            self.imageID = imageID
            self.model = model
            self.prompt = prompt
            self.width = width
            self.height = height
            self.steps = steps
            self.seed = seed
            self.path = path
            self.seconds = seconds
            self.createdAt = createdAt
        }
    }
}

/// 生成した画像に、お気に入り（星）を足した版。変わらないモデルは V1 のものをそのまま使う。
public enum LabSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [LabSchemaV1.ExperimentRecord.self, LabSchemaV1.AdapterRecord.self, GeneratedImageRecord.self]
    }

    @Model
    public final class GeneratedImageRecord {
        #Unique<GeneratedImageRecord>([\.imageID])

        public var imageID: UUID
        public var model: String
        public var prompt: String
        public var width: Int
        public var height: Int
        public var steps: Int?
        public var seed: Int
        public var path: String
        public var seconds: Double
        public var createdAt: Date
        public var isFavorite: Bool = false

        public init(
            imageID: UUID, model: String, prompt: String, width: Int, height: Int, steps: Int?, seed: Int, path: String,
            seconds: Double, createdAt: Date, isFavorite: Bool = false
        ) {
            self.imageID = imageID
            self.model = model
            self.prompt = prompt
            self.width = width
            self.height = height
            self.steps = steps
            self.seed = seed
            self.path = path
            self.seconds = seconds
            self.createdAt = createdAt
            self.isFavorite = isFavorite
        }
    }
}

public enum LabMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LabSchemaV1.self, LabSchemaV2.self] }
    public static var stages: [MigrationStage] {
        // 列を足しただけなので、軽い移行で済む
        [.lightweight(fromVersion: LabSchemaV1.self, toVersion: LabSchemaV2.self)]
    }
}

typealias ExperimentRecord = LabSchemaV1.ExperimentRecord
typealias AdapterRecord = LabSchemaV1.AdapterRecord
typealias GeneratedImageRecord = LabSchemaV2.GeneratedImageRecord

public enum LabStore {
    /// - Parameter url: 保存するファイル。nil ならメモリの上だけに置く（テスト用）。
    public static func makeContainer(url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LabSchemaV2.self)
        let configuration =
            if let url {
                ModelConfiguration(schema: schema, url: url)
            } else {
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
        return try ModelContainer(for: schema, migrationPlan: LabMigrationPlan.self, configurations: configuration)
    }

    public static func defaultURL() throws -> URL {
        try AppDataDirectory.url("Lab").appending(path: "lab.store")
    }
}

/// 実験の記録、アダプタ、生成した画像を SwiftData で持つ。
public actor SwiftDataLabRecordRepository: LabRecordRepository, ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    nonisolated private let broadcaster = ChangeBroadcaster()

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    public func experiments() async throws(LabError) -> [Experiment] {
        try storage {
            try modelContext.fetch(
                FetchDescriptor<ExperimentRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )
            .map { record in
                Experiment(
                    id: record.experimentID, kind: Experiment.Kind(rawValue: record.kind) ?? .generate,
                    model: record.model, prompt: record.prompt,
                    parameters: (try? JSONDecoder().decode([String: String].self, from: record.parameters)) ?? [:],
                    summary: record.summary, createdAt: record.createdAt)
            }
        }
    }

    public func save(_ experiment: Experiment) async throws(LabError) {
        try write {
            modelContext.insert(
                ExperimentRecord(
                    experimentID: experiment.id, kind: experiment.kind.rawValue, model: experiment.model,
                    prompt: experiment.prompt, parameters: try JSONEncoder().encode(experiment.parameters),
                    summary: experiment.summary, createdAt: experiment.createdAt))
        }
    }

    public func deleteExperiments(_ ids: [UUID]) async throws(LabError) {
        try write {
            try modelContext.delete(model: ExperimentRecord.self, where: #Predicate { ids.contains($0.experimentID) })
        }
    }

    public func adapters() async throws(LabError) -> [Adapter] {
        try storage {
            try modelContext.fetch(
                FetchDescriptor<AdapterRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )
            .map { record in
                Adapter(
                    id: record.adapterID, name: record.name, model: record.model, path: record.path,
                    settings: (try? JSONDecoder().decode(LoRASettings.self, from: record.settings)) ?? LoRASettings(),
                    source: record.source, finalLoss: record.finalLoss, createdAt: record.createdAt)
            }
        }
    }

    public func save(_ adapter: Adapter) async throws(LabError) {
        try write {
            modelContext.insert(
                AdapterRecord(
                    adapterID: adapter.id, name: adapter.name, model: adapter.model, path: adapter.path,
                    settings: try JSONEncoder().encode(adapter.settings), source: adapter.source,
                    finalLoss: adapter.finalLoss, createdAt: adapter.createdAt))
        }
    }

    public func deleteAdapter(_ id: UUID) async throws(LabError) {
        try write { try modelContext.delete(model: AdapterRecord.self, where: #Predicate { $0.adapterID == id }) }
    }

    public func images() async throws(LabError) -> [GeneratedImage] {
        try storage {
            try modelContext.fetch(
                FetchDescriptor<GeneratedImageRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )
            .map { record in
                GeneratedImage(
                    id: record.imageID, model: record.model, prompt: record.prompt, width: record.width,
                    height: record.height, steps: record.steps, seed: record.seed, path: record.path,
                    seconds: record.seconds, createdAt: record.createdAt, isFavorite: record.isFavorite)
            }
        }
    }

    public func save(_ image: GeneratedImage) async throws(LabError) {
        try write {
            modelContext.insert(
                GeneratedImageRecord(
                    imageID: image.id, model: image.model, prompt: image.prompt, width: image.width,
                    height: image.height, steps: image.steps, seed: image.seed, path: image.path,
                    seconds: image.seconds, createdAt: image.createdAt, isFavorite: image.isFavorite))
        }
    }

    public func deleteImage(_ id: UUID) async throws(LabError) {
        try write { try modelContext.delete(model: GeneratedImageRecord.self, where: #Predicate { $0.imageID == id }) }
    }

    public func deleteImages(_ ids: [UUID]) async throws(LabError) {
        guard !ids.isEmpty else { return }
        try write {
            try modelContext.delete(model: GeneratedImageRecord.self, where: #Predicate { ids.contains($0.imageID) })
        }
    }

    public func setImagesFavorite(_ ids: [UUID], isFavorite: Bool) async throws(LabError) {
        guard !ids.isEmpty else { return }
        try write {
            let records = try modelContext.fetch(
                FetchDescriptor<GeneratedImageRecord>(predicate: #Predicate { ids.contains($0.imageID) }))
            for record in records {
                record.isFavorite = isFavorite
            }
        }
    }

    nonisolated public func changes() -> AsyncStream<Void> {
        broadcaster.subscribe()
    }

    private func write(_ body: () throws -> Void) throws(LabError) {
        try storage {
            try body()
            try modelContext.save()
        }
        broadcaster.send()
    }

    private func storage<T>(_ body: () throws -> T) throws(LabError) -> T {
        do {
            return try body()
        } catch {
            throw .storage(error.localizedDescription)
        }
    }
}

/// アダプタと画像を、アプリのデータフォルダに置く。
public struct AppDataLabFiles: LabFileLocations {
    public init() {}

    public func newAdapterDirectory(name: String) -> String {
        let safe = name.replacing(/[\/:\\]/, with: "-")
        let stamp = Date.now.formatted(.localISO8601.year().month().day().time(includingFractionalSeconds: false))
            .replacing(":", with: "")
        let directory = (try? AppDataDirectory.url("Adapters")) ?? FileManager.default.temporaryDirectory
        return directory.appending(path: "\(safe)-\(stamp)", directoryHint: .isDirectory).path
    }

    public func newModelDirectory(name: String) -> String {
        let safe = name.replacing(/[\/:\\]/, with: "-")
        let directory = (try? AppDataDirectory.url("Models")) ?? FileManager.default.temporaryDirectory
        var candidate = directory.appending(path: safe, directoryHint: .isDirectory)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(safe)-\(number)", directoryHint: .isDirectory)
            number += 1
        }
        return candidate.path
    }

    public func newImagePath() -> String {
        let stamp = Date.now.formatted(.localISO8601.year().month().day().time(includingFractionalSeconds: true))
            .replacing(":", with: "")
        let directory = (try? AppDataDirectory.url("Images")) ?? FileManager.default.temporaryDirectory
        return directory.appending(path: "\(stamp).png").path
    }

    public func remove(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
