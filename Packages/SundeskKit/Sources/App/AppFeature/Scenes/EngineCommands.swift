//
//  EngineCommands.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import SwiftUI

/// メニューバーの「エンジン」メニュー。
struct EngineCommands: Commands {
    let engineStatus: EngineStatusViewModel

    var body: some Commands {
        CommandMenu("エンジン") {
            Button("エンジンを起動") {
                Task { await engineStatus.start() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!engineStatus.canStart)

            Button("エンジンを停止") {
                Task { await engineStatus.stop() }
            }
            .keyboardShortcut(".", modifiers: [.command, .option])
            .disabled(!engineStatus.canStop)
        }
    }
}
