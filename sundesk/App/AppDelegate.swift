//
//  AppDelegate.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskComposition
import SundeskDomain
import SundeskPresentation

/// アプリの起動と終了に合わせて、AI エンジンを起動・停止する。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ユニットテストはアプリをホストにして動くので、そのときはエンジンを起動しない
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard EngineSettings.startsAutomatically(), !isRunningUnitTests else { return }
        let engineStatus = Container.shared.engineStatusViewModel()
        Task { await engineStatus.start() }
    }

    /// エンジンのプロセスを残さないように、止め終わってから終了する。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let stopEngine = Container.shared.stopEngine()
        Task {
            await stopEngine()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
