//
//  BibTeXFile.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI
import UniformTypeIdentifiers

/// 書き出す BibTeX のファイル。
struct BibTeXFile: FileDocument {
    static let contentType = UTType(filenameExtension: "bib", conformingTo: .plainText) ?? .plainText
    static let readableContentTypes = [contentType]

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
