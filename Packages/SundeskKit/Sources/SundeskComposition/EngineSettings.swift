//
//  EngineSettings.swift
//  SundeskComposition
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskEngine

/// 設定画面で変えられるエンジンの設定。UserDefaults に保存する。
///
/// 設定画面（`@AppStorage`）と同じキーを使うので、キーはここで一元管理する。
public enum EngineSettings {
    public enum Key {
        public static let engineDirectory = "engine.directory"
        public static let uvExecutable = "engine.uvExecutable"
        public static let startsAutomatically = "engine.startsAutomatically"
    }

    public static var defaultEngineDirectory: String {
        EngineLocator.defaultEngineDirectory().path
    }

    public static var defaultUVExecutable: String {
        EngineLocator.findUV()?.path ?? "/opt/homebrew/bin/uv"
    }

    /// 起動時に読む。値が空なら既定値を使う。
    public static func configuration(defaults: UserDefaults = .standard) -> EngineConfiguration {
        let directory = defaults.string(forKey: Key.engineDirectory).flatMap { $0.isEmpty ? nil : $0 }
        let uv = defaults.string(forKey: Key.uvExecutable).flatMap { $0.isEmpty ? nil : $0 }
        return EngineConfiguration(
            engineDirectory: URL(filePath: directory ?? defaultEngineDirectory, directoryHint: .isDirectory),
            uvExecutable: URL(filePath: uv ?? defaultUVExecutable)
        )
    }

    public static func startsAutomatically(defaults: UserDefaults = .standard) -> Bool {
        // 起動引数（-engine.startsAutomatically NO）は文字列で届くので、bool(forKey:) で解釈する
        defaults.object(forKey: Key.startsAutomatically) == nil ? true : defaults.bool(forKey: Key.startsAutomatically)
    }
}
