//
//  FileAttachmentStoreTests.swift
//  SundeskDataTests
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import Testing

@testable import SundeskData

@Suite("PDF の置き場")
struct FileAttachmentStoreTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "sundesk-storage-\(UUID().uuidString)")

    @Test("文献ごとのフォルダに写し、差し替えと削除ができる")
    func importAndRemove() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileAttachmentStore(root: root)
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try Data("first".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let id = UUID()

        let path = try store.importPDF(source, for: id)
        try Data("second".utf8).write(to: source)
        _ = try store.importPDF(source, for: id)

        #expect(path == "\(id.uuidString)/\(source.lastPathComponent)")
        #expect(try String(contentsOf: store.url(for: path), encoding: .utf8) == "second")

        try store.removeAttachments(of: id)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: id.uuidString).path))
    }
}
