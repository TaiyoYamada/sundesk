//
//  AppDelegate.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import EngineFeature
import FactoryKit
import NotesFeature
import SundeskDomain

/// アプリの起動と終了に合わせて、AI エンジンを起動・停止する。終了する前に、編集を保存する。
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // ユニットテストはアプリをホストにして動くので、そのときはエンジンを起動しない
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard Container.shared.resolvedSettings().startsEngineAutomatically, !isRunningUnitTests else { return }
        let engineStatus = Container.shared.engineStatusViewModel()
        Task { await engineStatus.start() }
    }

    /// 保存していない編集を保存し、エンジンのプロセスを止め終わってから終了する。
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let openDocuments = Container.shared.openDocumentRegistry()
        let stopEngine = Container.shared.stopEngine()
        Task {
            await openDocuments.saveAll()
            await stopEngine()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
