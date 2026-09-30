//
//  FileSystemScriptRepositoryTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskData
import SundeskDomain
import Testing

@Suite("FileSystemScriptRepository")
struct FileSystemScriptRepositoryTests {
    @Test("スクリプトを .py として保存し、名前の順に読み戻し、消せる")
    func roundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sundesk-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileSystemScriptRepository(directory: { directory })

        try await repository.save(Script(name: "層/ノルム", code: "print(1)"))
        try await repository.save(Script(name: "あ", code: "x = 2"))

        #expect(try await repository.scripts().map(\.name) == ["あ", "層-ノルム"])
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "層-ノルム.py").path))
        try await repository.delete(named: "あ")
        #expect(try await repository.scripts().map(\.code) == ["print(1)"])
    }

    @Test("名前を変える。同じ名前のスクリプトがあれば変えない")
    func rename() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sundesk-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileSystemScriptRepository(directory: { directory })
        try await repository.save(Script(name: "a", code: "1"))
        try await repository.save(Script(name: "b", code: "2"))

        try await repository.rename(named: "a", to: "c")
        await #expect(throws: LabError.self) { try await repository.rename(named: "b", to: "c") }

        #expect(try await repository.scripts() == [Script(name: "b", code: "2"), Script(name: "c", code: "1")])
    }
}
