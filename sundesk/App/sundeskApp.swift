//
//  sundeskApp.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppFeature
import SwiftUI

/// アプリの入口。画面の組み立てはすべて AppFeature（Packages/SundeskKit）にある。
@main
struct SundeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SundeskScenes()
    }
}
