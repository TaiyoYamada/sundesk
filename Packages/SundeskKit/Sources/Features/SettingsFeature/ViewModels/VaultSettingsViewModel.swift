//
//  VaultSettingsViewModel.swift
//  SettingsFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 設定画面の「ライブラリ」。場所、書き出し、戻し、見本のライブラリへの切り替え。
@MainActor
@Observable
public final class VaultSettingsViewModel {
    /// 見本のライブラリを使うか（開発とテスト用）。
    public var usesSampleLibrary: Bool {
        didSet {
            guard usesSampleLibrary != oldValue else { return }
            let path = usesSampleLibrary ? samplePath : ""
            updateSettings { $0.vaultDirectory = path }
            needsRestart = true
        }
    }
    public private(set) var needsRestart = false
    public private(set) var isWorking = false
    public var message: String?

    /// 本物のライブラリの場所。
    public let libraryPath: String
    @ObservationIgnored private let samplePath: String
    @ObservationIgnored private let updateSettings: any UpdateSettingsUseCase
    @ObservationIgnored private let library: any ManageLibraryUseCase
    @ObservationIgnored private let currentPath: String

    public init(
        loadSettings: any LoadSettingsUseCase, updateSettings: any UpdateSettingsUseCase,
        library: any ManageLibraryUseCase, samplePath: String
    ) {
        let settings = loadSettings()
        self.libraryPath = loadSettings.defaults.vaultDirectory
        self.samplePath = samplePath
        self.currentPath =
            settings.vaultDirectory.isEmpty ? loadSettings.defaults.vaultDirectory : settings.vaultDirectory
        self.usesSampleLibrary = !settings.vaultDirectory.isEmpty && settings.vaultDirectory == samplePath
        self.updateSettings = updateSettings
        self.library = library
    }

    /// 今使っているライブラリ（「Finder で開く」に使う）。
    public var effectiveVaultURL: URL {
        URL(filePath: currentPath, directoryHint: .isDirectory)
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
