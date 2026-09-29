//
//  FileSystemStudySections.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// study-artifact のノートのフォルダの中を、ファイルシステムで調べる。
public struct FileSystemStudySections: ListStudySectionsUseCase {
    public init() {}

    public func callAsFunction(in studyDirectory: String) -> [String] {
        let fileManager = FileManager.default
        let notes = ResearchSources.studyNotesPath(studyDirectory) { fileManager.fileExists(atPath: $0) }
        let names = (try? fileManager.contentsOfDirectory(atPath: notes)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            let path = (notes as NSString).appendingPathComponent(name)
            return !name.hasPrefix(".") && fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
