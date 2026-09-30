//
//  VaultMount.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

/// ライブラリの外にあるフォルダを、読むだけでつなぐ（~/Research や study-artifact）。
///
/// つないだフォルダは、ライブラリの一番上に `name` のフォルダとして現れる。
/// コピーはしないので、元の場所で書き換えるとすぐに反映される。sundesk からは書き込まない。
public struct VaultMount: Equatable, Sendable {
    /// どのファイルを見せるか。
    public enum Filter: Equatable, Sendable {
        /// すべて。
        case all
        /// 一番上のフォルダのうち `sections` だけ。`taggedFolders` のフォルダは、タグが `tags` と重なるノートだけ。
        case sections(Set<String>, taggedFolders: Set<String>, tags: Set<String>)
    }

    /// ライブラリの中での名前（一番上のフォルダ名）。
    public let name: String
    public let url: URL
    public let filter: Filter

    public init(name: String, url: URL, filter: Filter = .all) {
        self.name = name
        self.url = url
        self.filter = filter
    }

    /// パスがこのつないだフォルダの中か。
    public func contains(_ path: String) -> Bool {
        path == name || path.hasPrefix(name + "/")
    }

    /// つないだフォルダの中でのパス（`Research/paper/a.pdf` → `paper/a.pdf`）。
    public func relativePath(of path: String) -> String? {
        guard contains(path) else { return nil }
        return path == name ? "" : String(path.dropFirst(name.count + 1))
    }
}

/// 研究のデータを読むところの名前と既定値。
public enum ResearchSources {
    /// ~/Research をつなぐ名前。
    public static let researchName = "Research"
    /// study-artifact をつなぐ名前。
    public static let studyName = "study-artifact"

    /// study-artifact の中で、研究に関係するところ（既定）。
    public static let defaultStudySections = [
        "02-最適化", "07-量子化学", "08-量子コンピューティング", "09-量子アルゴリズム", "10-量子シミュレーション",
        "14-研究", "90-論文メモ",
    ]

    /// study-artifact の `_inbox` から拾うノートのタグ（どれかが付いていれば研究のノートとみなす）。
    public static let defaultInboxTags: Set<String> = [
        "最適化", "群知能", "進化計算", "量子アニーリング", "量子最適化", "CMA-ES", "ABC", "PSO", "VQE", "QAOA",
        "SQA", "ACO", "研究", "実験設計", "量子計算", "量子アルゴリズム",
    ]

    public static let inboxFolder = "_inbox"

    /// study-artifact のノートのフォルダ。リポジトリのルートを指定しても、notes/ の中を見る。
    public static func studyNotesPath(_ study: String, fileExists: (String) -> Bool) -> String {
        let studyPath = (study as NSString).expandingTildeInPath
        let notes = (studyPath as NSString).appendingPathComponent("notes")
        return fileExists(notes) ? notes : studyPath
    }

    /// 設定から、つなぐフォルダを作る。フォルダがなければつながない。
    public static func mounts(
        research: String, study: String, studySections: [String], fileExists: (String) -> Bool
    ) -> [VaultMount] {
        var mounts: [VaultMount] = []
        let researchPath = (research as NSString).expandingTildeInPath
        if !research.isEmpty, fileExists(researchPath) {
            mounts.append(VaultMount(name: researchName, url: URL(filePath: researchPath, directoryHint: .isDirectory)))
        }
        let studyRoot = studyNotesPath(study, fileExists: fileExists)
        if !study.isEmpty, fileExists(studyRoot) {
            let sections = Set(studySections.isEmpty ? defaultStudySections : studySections)
            mounts.append(
                VaultMount(
                    name: studyName, url: URL(filePath: studyRoot, directoryHint: .isDirectory),
                    filter: .sections(
                        sections.union([inboxFolder]), taggedFolders: [inboxFolder], tags: defaultInboxTags)))
        }
        return mounts
    }
}
