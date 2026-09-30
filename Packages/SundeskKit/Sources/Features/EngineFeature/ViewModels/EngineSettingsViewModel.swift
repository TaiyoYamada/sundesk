//
//  EngineSettingsViewModel.swift
//  EngineFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import Observation
import SundeskDomain

/// 設定画面の「エンジン」。入力するたびに保存する。
@MainActor
@Observable
public final class EngineSettingsViewModel {
    public var engineDirectory: String {
        didSet { updateSettings { $0.engineDirectory = engineDirectory } }
    }
    public var uvExecutable: String {
        didSet { updateSettings { $0.uvExecutable = uvExecutable } }
    }
    public var startsAutomatically: Bool {
        didSet { updateSettings { $0.startsEngineAutomatically = startsAutomatically } }
    }

    /// 空欄のときに使う値（入力欄の薄い文字に出す）。
    public let defaultEngineDirectory: String
    public let defaultUVExecutable: String

    @ObservationIgnored private let updateSettings: any UpdateSettingsUseCase

    public init(loadSettings: any LoadSettingsUseCase, updateSettings: any UpdateSettingsUseCase) {
        let settings = loadSettings()
        engineDirectory = settings.engineDirectory
        uvExecutable = settings.uvExecutable
        startsAutomatically = settings.startsEngineAutomatically
        defaultEngineDirectory = loadSettings.defaults.engineDirectory
        defaultUVExecutable = loadSettings.defaults.uvExecutable
        self.updateSettings = updateSettings
    }
}
