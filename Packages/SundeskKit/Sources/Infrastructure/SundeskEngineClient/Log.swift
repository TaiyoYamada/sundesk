//
//  Log.swift
//  SundeskEngineClient
//
//  Created by 山田大陽 on 2026/09/29.
//

import OSLog

enum Log {
    static let subsystem = "com.taiyou.sundesk"

    /// エンジンのプロセスの起動や停止。
    static let process = Logger(subsystem: subsystem, category: "engine.process")
    /// エンジン（Python）自身の標準出力と標準エラー。
    static let output = Logger(subsystem: subsystem, category: "engine.output")
    /// Instruments の Points of Interest に区間を出す。
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
