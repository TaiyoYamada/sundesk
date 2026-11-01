//
//  AppDataDirectory.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// アプリのデータフォルダ（~/Library/Application Support/com.taiyou.sundesk）。
public enum AppDataDirectory {
    /// その下のフォルダ。なければ作る。
    public static func url(_ folder: String) throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "com.taiyou.sundesk/\(folder)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
