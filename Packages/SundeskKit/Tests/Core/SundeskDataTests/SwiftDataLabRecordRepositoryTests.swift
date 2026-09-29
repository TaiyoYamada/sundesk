//
//  SwiftDataLabRecordRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
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
}
