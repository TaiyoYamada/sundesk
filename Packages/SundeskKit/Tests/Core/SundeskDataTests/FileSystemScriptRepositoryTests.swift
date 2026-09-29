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
}
