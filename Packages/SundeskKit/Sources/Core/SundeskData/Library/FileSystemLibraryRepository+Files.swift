//
//  FileSystemLibraryRepository+Files.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

extension FileSystemLibraryRepository {
    // MARK: - 書き出しと戻し

    public func export(to destination: URL) async throws(LibraryError) {
        try storage {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: rootURL(), to: destination)
        }
    }

    public func restore(from source: URL) async throws(LibraryError) {
        let hasLibrary = LibrarySection.allCases.contains { exists(source.appending(path: $0.folder)) }
        guard hasLibrary else { throw .invalid("選んだフォルダは sundesk のライブラリではありません") }
        let root = rootURL()
        try storage {
            if exists(root) {
                // 念のため、今のライブラリは横に残してから置き換える
                let stamp = Date.now.formatted(
                    .localISO8601.year().month().day().time(includingFractionalSeconds: false)
                )
                .replacing(":", with: "")
                let backup = root.deletingLastPathComponent().appending(path: "Library-\(stamp)")
                try fileManager.moveItem(at: root, to: backup)
            }
            try fileManager.copyItem(at: source, to: root)
        }
    }

    // MARK: - 補助（名前の重なりを避ける、失敗を LibraryError に直す、など）

    func subfolders(of directory: URL) -> [URL] {
        ((try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func uniqueKey(_ base: String, in directory: URL) -> String {
        var key = base
        var number = 2
        while exists(directory.appending(path: key)) {
            key = "\(base)-\(number)"
            number += 1
        }
        return key
    }

    func uniqueName(_ name: String, in directory: URL) -> String {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var number = 2
        while exists(directory.appending(path: candidate)) {
            candidate = ext.isEmpty ? "\(stem)-\(number)" : "\(stem)-\(number).\(ext)"
            number += 1
        }
        return candidate
    }

    func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    func copy(_ source: URL, to destination: URL) throws {
        if exists(destination) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    func storage<T>(_ body: () throws -> T) throws(LibraryError) -> T {
        do {
            return try body()
        } catch let error as LibraryError {
            throw error
        } catch {
            throw .storage(error.localizedDescription)
        }
    }
}
