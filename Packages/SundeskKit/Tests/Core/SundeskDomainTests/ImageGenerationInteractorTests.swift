//
//  ImageGenerationInteractorTests.swift
//  SundeskDomainTests
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain
import Testing

@Suite("ImageGenerationInteractor")
struct ImageGenerationInteractorTests {
    private func image(_ name: String) -> GeneratedImage {
        GeneratedImage(
            id: UUID(), model: "z-image-turbo", prompt: name, width: 512, height: 512, steps: nil, seed: 1,
            path: "/images/\(name).png", seconds: 1, createdAt: .now)
    }

    @Test("まとめて消すと、記録とファイルの両方を消す")
    func deletesMany() async throws {
        let records = LabRecordsSpy()
        let files = FilesStub()
        let generation = ImageGenerationInteractor(engine: LabEngineStub(), records: records, files: files)
        let images = [image("a"), image("b"), image("c")]
        for image in images {
            try await records.save(image)
        }

        try await generation.delete(Array(images.prefix(2)))

        #expect(await records.savedImages.map(\.prompt) == ["c"])
        #expect(files.removed.value == ["/images/a.png", "/images/b.png"])
    }

    @Test("何も選んでいなければ、何も消さない")
    func deletesNothing() async throws {
        let records = LabRecordsSpy()
        let files = FilesStub()
        let generation = ImageGenerationInteractor(engine: LabEngineStub(), records: records, files: files)
        try await records.save(image("a"))

        try await generation.delete([])

        #expect(await records.savedImages.count == 1)
        #expect(files.removed.value.isEmpty)
    }

    @Test("お気に入りを付け外しできる")
    func favorites() async throws {
        let records = LabRecordsSpy()
        let generation = ImageGenerationInteractor(engine: LabEngineStub(), records: records, files: FilesStub())
        let first = image("a")
        let second = image("b")

        try await generation.setFavorite([first, second], isFavorite: true)
        #expect(await records.favoriteImageIDs == [first.id, second.id])
        try await generation.setFavorite([first], isFavorite: false)
        #expect(await records.favoriteImageIDs == [second.id])
    }
}
