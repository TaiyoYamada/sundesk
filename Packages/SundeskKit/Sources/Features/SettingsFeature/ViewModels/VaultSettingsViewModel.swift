//
//  VaultSettingsViewModel.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 設定画面の「ライブラリ」。場所、読むだけでつなぐ研究のデータ、書き出し、戻し。
@MainActor
@Observable
public final class VaultSettingsViewModel {
    /// 研究のデータのフォルダ（~/Research）。
    public var researchDirectory: String {
        didSet {
            let value = researchDirectory == defaultResearch ? "" : researchDirectory
            save { $0.researchDirectory = value }
        }
    }
    /// study-artifact のフォルダ。
    public var studyDirectory: String {
        didSet {
            let value = studyDirectory == defaultStudy ? "" : studyDirectory
            save { $0.studyDirectory = value }
            availableSections = listSections(in: studyDirectory)
        }
    }
    /// study-artifact の中で読むフォルダ。
    public private(set) var selectedSections: Set<String>
    /// study-artifact の中にあるフォルダ。
    public private(set) var availableSections: [String] = []
    public private(set) var needsRestart = false
    public private(set) var isWorking = false
    public var message: String?

    /// 本物のライブラリの場所。
    public let libraryPath: String
    @ObservationIgnored private let defaultResearch: String
    @ObservationIgnored private let defaultStudy: String
    @ObservationIgnored private let updateSettings: any UpdateSettingsUseCase
    @ObservationIgnored private let library: any ManageLibraryUseCase
    @ObservationIgnored private let listSections: any ListStudySectionsUseCase

    public init(
        loadSettings: any LoadSettingsUseCase, updateSettings: any UpdateSettingsUseCase,
        library: any ManageLibraryUseCase, listSections: any ListStudySectionsUseCase
    ) {
        let settings = loadSettings()
        let resolved = settings.resolved(with: loadSettings.defaults)
        self.libraryPath = resolved.vaultDirectory
        self.defaultResearch = loadSettings.defaults.researchDirectory
        self.defaultStudy = loadSettings.defaults.studyDirectory
        self.researchDirectory = resolved.researchDirectory
        self.studyDirectory = resolved.studyDirectory
        self.selectedSections = Set(
            settings.studySections.isEmpty ? ResearchSources.defaultStudySections : settings.studySections)
        self.updateSettings = updateSettings
        self.library = library
        self.listSections = listSections
        self.availableSections = listSections(in: resolved.studyDirectory)
    }

    /// 今使っているライブラリ（「Finder で開く」に使う）。
    public var effectiveVaultURL: URL {
        URL(filePath: libraryPath, directoryHint: .isDirectory)
    }

    public func isSelected(_ section: String) -> Bool {
        selectedSections.contains(section)
    }

    public func setSection(_ section: String, selected: Bool) {
        if selected { selectedSections.insert(section) } else { selectedSections.remove(section) }
        let sections = availableSections.filter(selectedSections.contains)
        save { $0.studySections = Set(sections) == Set(ResearchSources.defaultStudySections) ? [] : sections }
    }

    /// 選んだフォルダの中に、ライブラリを丸ごと書き出す。
    public func export(into folder: URL) async {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacing(":", with: "")
        let destination = folder.appending(path: "sundesk-library-\(stamp)", directoryHint: .isDirectory)
        await work {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            try await self.library.export(to: destination)
            return "\(destination.path) に書き出しました"
        }
    }

    /// 書き出したライブラリから戻す（今のものは横に残す）。
    public func restore(from folder: URL) async {
        await work {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            try await self.library.restore(from: folder)
            self.needsRestart = true
            return "戻しました。今までのライブラリは、同じ場所に日付を付けて残しています"
        }
    }

    private func save(_ change: (inout AppSettings) -> Void) {
        updateSettings(change)
        needsRestart = true
    }

    private func work(_ body: @escaping () async throws -> String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            message = try await body()
        } catch let error as LibraryError {
            message = error.message
        } catch {
            message = error.localizedDescription
        }
    }
}
