//
//  FileSystemLibraryRepository+Research.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation
import SundeskDomain

/// 読むだけでつないだ研究のデータ（~/Research）の論文を、写さずに論文にする。
extension FileSystemLibraryRepository {
    /// 研究のデータで、論文の PDF を置くフォルダ。
    static let researchPaperFolders = ["paper", "papers"]

    public func unlinkedResearchPDFs() async -> [String] {
        guard let research = mounts().first(where: { $0.name == ResearchSources.researchName }) else { return [] }
        let linked = Set(((try? await papers()) ?? []).compactMap(\.linkedPDF))
        return Self.researchPDFs(in: research).filter { !linked.contains($0) }.sorted()
    }

    /// 研究のデータの paper/ にある PDF の、ライブラリの中でのパス。
    static func researchPDFs(in research: VaultMount) -> [String] {
        var paths: [String] = []
        for folderName in researchPaperFolders {
            let directory = research.url.appending(path: folderName, directoryHint: .isDirectory)
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "pdf" {
                let inside = file.standardizedFileURL.path
                    .replacingOccurrences(of: research.url.standardizedFileURL.path + "/", with: "")
                paths.append("\(research.name)/\(inside)")
            }
        }
        return paths
    }

    public func linkPaper(_ metadata: PaperMetadata, pdf: String) async throws(LibraryError) -> Paper {
        let key = uniqueKey(LibraryText.paperKey(for: metadata), in: folder(.papers))
        let directory = folder(.papers).appending(path: key, directoryHint: .isDirectory)
        let paper = Paper(
            key: key, metadata: metadata, status: .unread, tags: [], added: .now, pdfPath: pdf, linkedPDF: pdf)
        try storage {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(
                LibraryText.frontmatter(for: paper) + "# \(metadata.title)\n\n## 要点\n\n## メモ\n",
                to: directory.appending(path: "note.md"))
        }
        return paper
    }
}
