//
//  VaultUseCases.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation

// MARK: - 木を読む

public protocol LoadVaultTreeUseCase: Sendable {
    func callAsFunction() async throws(VaultError) -> VaultNode
}

public struct LoadVaultTreeInteractor: LoadVaultTreeUseCase {
    private let vault: any VaultRepository

    public init(vault: any VaultRepository) {
        self.vault = vault
    }

    public func callAsFunction() async throws(VaultError) -> VaultNode {
        try await vault.loadTree()
    }
}

// MARK: - 変更を見張る

public protocol ObserveVaultChangesUseCase: Sendable {
    func callAsFunction() -> AsyncStream<Void>
}

public struct ObserveVaultChangesInteractor: ObserveVaultChangesUseCase {
    private let vault: any VaultRepository

    public init(vault: any VaultRepository) {
        self.vault = vault
    }

    public func callAsFunction() -> AsyncStream<Void> {
        vault.changes()
    }
}

// MARK: - ファイルを開く

public protocol OpenDocumentUseCase: Sendable {
    func callAsFunction(path: String) async throws(VaultError) -> Document
}

public struct OpenDocumentInteractor: OpenDocumentUseCase {
    private let vault: any VaultRepository
    private let markdown: any MarkdownParsing

    public init(vault: any VaultRepository, markdown: any MarkdownParsing) {
        self.vault = vault
        self.markdown = markdown
    }

    public func callAsFunction(path: String) async throws(VaultError) -> Document {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let kind = FileKind(fileName: name)
        let info = try await vault.fileInfo(at: path)
        let url = vault.fileURL(for: path)

        let content: DocumentContent
        switch kind {
        case .markdown:
            let source = try await vault.readText(at: path)
            content = .markdown(source: source, analysis: markdown.analyze(source, path: path))
        case .html:
            content = .html(source: try await vault.readText(at: path), url: url)
        case .code, .text:
            content = .text(source: try await vault.readText(at: path))
        case .image:
            content = .image(url)
        case .pdf:
            content = .pdf(url)
        case .folder, .other:
            content = .other(url)
        }
        return Document(path: path, name: name, kind: kind, info: info, content: content)
    }
}

// MARK: - リンクを解決する

public protocol ResolveLinkUseCase: Sendable {
    /// リンク先のファイルのパス。見つからなければ nil。
    func callAsFunction(_ target: String, exact: Bool) async throws(VaultError) -> String?
}

public struct ResolveLinkInteractor: ResolveLinkUseCase {
    private let vault: any VaultRepository

    public init(vault: any VaultRepository) {
        self.vault = vault
    }

    public func callAsFunction(_ target: String, exact: Bool) async throws(VaultError) -> String? {
        let tree = try await vault.loadTree()
        return LinkResolver(paths: tree.files.map(\.path)).resolve(target, exact: exact)
    }
}

// MARK: - 保存する

public protocol SaveDocumentUseCase: Sendable {
    func callAsFunction(_ text: String, to path: String) async throws(VaultError)
}

public struct SaveDocumentInteractor: SaveDocumentUseCase {
    private let vault: any VaultRepository

    public init(vault: any VaultRepository) {
        self.vault = vault
    }

    public func callAsFunction(_ text: String, to path: String) async throws(VaultError) {
        try await vault.writeText(text, to: path)
    }
}

// MARK: - ファイルの場所

public protocol LocateFileUseCase: Sendable {
    /// Vault のルートからのパスを、ファイルの場所にする（Finder で表示するときなど）。
    func callAsFunction(_ path: String) -> URL
    /// Vault のフォルダの場所。
    func vaultRoot() -> URL
}

public struct LocateFileInteractor: LocateFileUseCase {
    private let vault: any VaultRepository

    public init(vault: any VaultRepository) {
        self.vault = vault
    }

    public func callAsFunction(_ path: String) -> URL {
        vault.fileURL(for: path)
    }

    public func vaultRoot() -> URL {
        vault.rootURL()
    }
}
