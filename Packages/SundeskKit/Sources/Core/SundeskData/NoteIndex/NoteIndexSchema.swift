//
//  NoteIndexSchema.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SwiftData

/// ノートの索引のスキーマ。変えるときは V2 を足し、移行の段階を書く。
public enum NoteIndexSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [NoteRecord.self, NoteLinkRecord.self, IndexMetadataRecord.self]
    }

    @Model
    public final class NoteRecord {
        #Unique<NoteRecord>([\.path])
        #Index<NoteRecord>([\.path])

        public var path: String
        public var title: String
        public var tags: [String]
        public var body: String
        /// 更新日時と大きさ。変わったノートだけを読み直すために使う。
        public var stamp: String

        public init(path: String, title: String, tags: [String], body: String, stamp: String) {
            self.path = path
            self.title = title
            self.tags = tags
            self.body = body
            self.stamp = stamp
        }
    }

    /// ノートからノート（やファイル）へのリンク。整数の表ではなく、パスで持つ（規模が小さいため）。
    @Model
    public final class NoteLinkRecord {
        #Index<NoteLinkRecord>([\.sourcePath], [\.targetPath])

        public var sourcePath: String
        public var targetPath: String

        public init(sourcePath: String, targetPath: String) {
            self.sourcePath = sourcePath
            self.targetPath = targetPath
        }
    }

    @Model
    public final class IndexMetadataRecord {
        #Unique<IndexMetadataRecord>([\.key])

        public var key: String
        public var value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }
}

public enum NoteIndexMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [NoteIndexSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

typealias NoteRecord = NoteIndexSchemaV1.NoteRecord
typealias NoteLinkRecord = NoteIndexSchemaV1.NoteLinkRecord
typealias IndexMetadataRecord = NoteIndexSchemaV1.IndexMetadataRecord

/// 索引の保存先を作る。
public enum NoteIndexStore {
    /// - Parameter url: 保存するファイル。nil ならメモリの上だけに置く（テスト用）。
    public static func makeContainer(url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NoteIndexSchemaV1.self)
        let configuration =
            if let url {
                ModelConfiguration(schema: schema, url: url)
            } else {
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
        return try ModelContainer(
            for: schema, migrationPlan: NoteIndexMigrationPlan.self, configurations: configuration)
    }

    /// Vault ごとに別のファイルにする（Vault を切り替えても索引が混ざらない）。
    public static func defaultURL(forVault vault: URL) throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "com.taiyou.sundesk/NoteIndex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in vault.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return directory.appending(path: "\(String(hash, radix: 16)).store")
    }
}
