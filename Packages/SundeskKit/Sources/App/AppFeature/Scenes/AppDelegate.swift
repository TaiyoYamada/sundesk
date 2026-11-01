//
//  AppDelegate.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SettingsFeature

/// 起動したときに、保存してある外観を当てる。
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.stored.apply()
    }
}
