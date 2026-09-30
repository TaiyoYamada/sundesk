//
//  SwiftDataLabRecordRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import SwiftData
import Testing

@Suite("SwiftDataLabRecordRepository")
struct SwiftDataLabRecordRepositoryTests {
    private func makeRepository() throws -> SwiftDataLabRecordRepository {
        SwiftDataLabRecordRepository(modelContainer: try LabStore.makeContainer(url: nil))
    }

    @Test("実験の記録を新しい順に読み戻し、消せる")
    func experiments() async throws {
        let repository = try makeRepository()
        let old = Experiment(
            kind: .tokenize, model: "m", prompt: "a", parameters: [:], summary: "1", createdAt: .distantPast)
        let new = Experiment(kind: .attention, model: "m", prompt: "b", parameters: ["層": "3"], summary: "2")

        try await repository.save(old)
        try await repository.save(new)

        #expect(try await repository.experiments() == [new, old])
        try await repository.deleteExperiment(new.id)
        #expect(try await repository.experiments() == [old])
    }

    @Test("アダプタと画像を保存し、読み戻せる")
    func adaptersAndImages() async throws {
        let repository = try makeRepository()
        let adapter = Adapter(
            id: UUID(), name: "数学", model: "m", path: "/a", settings: LoRASettings(iterations: 50), source: "数学（3 本）",
            finalLoss: 1.2, createdAt: .now)
        let image = GeneratedImage(
            id: UUID(), model: "z-image-turbo", prompt: "猫", width: 512, height: 512, steps: 9, seed: 42,
            path: "/i.png",
            seconds: 12, createdAt: .now)

        try await repository.save(adapter)
        try await repository.save(image)

        #expect(try await repository.adapters() == [adapter])
        #expect(try await repository.images() == [image])
        try await repository.deleteAdapter(adapter.id)
        try await repository.deleteImage(image.id)
        #expect(try await repository.adapters().isEmpty)
        #expect(try await repository.images().isEmpty)
    }

    @Test("画像をまとめて消し、お気に入りを付け外しできる")
    func deletesImagesAndFavorites() async throws {
        let repository = try makeRepository()
        let images = (0..<3).map { index in
            GeneratedImage(
                id: UUID(), model: "m", prompt: "\(index)", width: 512, height: 512, steps: nil, seed: index,
                path: "/\(index).png", seconds: 1, createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        for image in images {
            try await repository.save(image)
        }

        try await repository.setImagesFavorite([images[0].id, images[2].id], isFavorite: true)
        #expect(try await repository.images().filter(\.isFavorite).map(\.prompt) == ["2", "0"])

        try await repository.deleteImages([images[0].id, images[1].id])
        let rest = try await repository.images()
        #expect(rest.map(\.prompt) == ["2"])
        #expect(rest.first?.isFavorite == true)
    }

    @Test("前の版（お気に入りのない版）の記録を、そのまま読み込める")
    func migratesFromV1() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "lab.store")
        let id = UUID()
        do {
            let schema = Schema(versionedSchema: LabSchemaV1.self)
            let container = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            context.insert(
                LabSchemaV1.GeneratedImageRecord(
                    imageID: id, model: "m", prompt: "前の画像", width: 512, height: 512, steps: 4, seed: 7, path: "/a.png",
                    seconds: 3, createdAt: .now))
            try context.save()
        }

        let repository = SwiftDataLabRecordRepository(modelContainer: try LabStore.makeContainer(url: url))
        let images = try await repository.images()

        #expect(images.map(\.id) == [id])
        #expect(images.first?.isFavorite == false)
        try await repository.setImagesFavorite([id], isFavorite: true)
        #expect(try await repository.images().first?.isFavorite == true)
    }
}
