//
//  FileAttachmentStore.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// 添付の PDF を、文献ごとのフォルダ（`<保存先>/<文献の ID>/<元のファイル名>`）に置く。
public struct FileAttachmentStore: AttachmentStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func importPDF(_ source: URL, for referenceID: UUID) throws(LibraryError) -> String {
        let name = source.pathExtension.lowercased() == "pdf" ? source.lastPathComponent : "paper.pdf"
        let path = "\(referenceID.uuidString)/\(name)"
        let destination = url(for: path)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw .storage(error.localizedDescription)
        }
        return path
    }

    public func url(for path: String) -> URL {
        root.appending(path: path)
    }

    public func removeAttachments(of referenceID: UUID) throws(LibraryError) {
        let folder = root.appending(path: referenceID.uuidString, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            throw .storage(error.localizedDescription)
        }
    }
}
