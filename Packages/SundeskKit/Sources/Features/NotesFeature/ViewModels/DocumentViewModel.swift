//
//  DocumentViewModel.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import OSLog
import Observation
import SundeskDomain

/// 開いた 1 つのファイル。どう描くか、編集した本文の自動保存、インスペクタに何を出すかを受け持つ。
@MainActor
@Observable
public final class DocumentViewModel {
    /// 表示のモード。Markdown は 3 つ（Obsidian と同じ）、HTML は閲覧とソース、コードとテキストはソースだけ。
    public enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
        /// 編集しながら整形して見る（カーソルのない行の記号を隠す）。
        case livePreview
        /// 記号をすべて見せて編集する。
        case source
        /// 整形して読む（編集しない）。
        case reading

        public var id: Self { self }

        public var title: String {
            switch self {
            case .livePreview: "ライブプレビュー"
            case .source: "ソース"
            case .reading: "閲覧"
            }
        }

        public var systemImage: String {
            switch self {
            case .livePreview: "pencil.line"
            case .source: "chevron.left.forwardslash.chevron.right"
            case .reading: "book"
            }
        }

        var isEditing: Bool { self != .reading }
    }

    public let path: String
    /// このファイルで選べるモード。
    public let availableModes: [DisplayMode]
    public var displayMode: DisplayMode {
        didSet {
            if displayMode.isEditing { lastEditingMode = displayMode }
            // 閲覧に切り替えたら保存しておく（HTML はファイルを読み直して描くので）
            if displayMode == .reading { Task { await flush() } }
        }
    }
    public private(set) var saveState: SaveState = .saved
    public private(set) var backlinks: [NoteLinkItem] = []
    /// 目次で選ばれた見出し。View はここへスクロールし、終わったら nil に戻す。
    public var scrollTarget: OutlineItem?
    /// 保存や読み込みのたびに増える（HTML の表示を読み直すきっかけ）。
    public private(set) var revision = 0

    /// 編集中の本文。書き換えると、少し待ってから自動で保存する。
    public var text: String {
        get { storedText }
        set {
            guard isEditable, newValue != storedText else { return }
            storedText = newValue
            didEdit()
        }
    }

    @ObservationIgnored private let kind: FileKind
    @ObservationIgnored private let openDocument: any OpenDocumentUseCase
    @ObservationIgnored private let saveDocument: any SaveDocumentUseCase
    @ObservationIgnored private let analyzeNote: any AnalyzeNoteUseCase
    @ObservationIgnored private let findBacklinks: any FindBacklinksUseCase
    @ObservationIgnored private let locateFile: any LocateFileUseCase
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private var lastEditingMode: DisplayMode
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var saveInFlight: Task<Void, Never>?
    /// 読み込んだら移る行（`reveal(line:)`）。
    @ObservationIgnored private var pendingLine: Int?
    /// ファイルに書かれている本文（読み込んだもの、または最後に保存したもの）。
    private var savedText: String?

    private var storedText = ""
    private var document: Document?
    private var analysis: NoteAnalysis?
    private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.taiyou.sundesk", category: "document")

    public init(
        path: String,
        openDocument: any OpenDocumentUseCase,
        saveDocument: any SaveDocumentUseCase,
        analyzeNote: any AnalyzeNoteUseCase,
        findBacklinks: any FindBacklinksUseCase,
        locateFile: any LocateFileUseCase,
        isReadOnly: Bool = false,
        autosaveDelay: Duration = .seconds(1)
    ) {
        self.path = path
        let kind = FileKind(fileName: path.split(separator: "/").last.map(String.init) ?? path)
        self.kind = kind
        self.isReadOnly = isReadOnly
        self.availableModes =
            switch kind {
            // 読むだけのノートは閲覧から開く（ソースも見られる）
            case .markdown: isReadOnly ? [.reading, .source] : [.livePreview, .source, .reading]
            case .html: [.reading, .source]
            case .code, .text: [.source]
            case .image, .pdf, .other, .folder: [.reading]
            }
        let initialMode = availableModes[0]
        self.displayMode = initialMode
        self.lastEditingMode =
            initialMode.isEditing ? initialMode : (availableModes.first { $0.isEditing } ?? initialMode)
        self.openDocument = openDocument
        self.saveDocument = saveDocument
        self.analyzeNote = analyzeNote
        self.findBacklinks = findBacklinks
        self.locateFile = locateFile
        self.autosaveDelay = autosaveDelay
    }

    // MARK: - 表示

    public var title: String {
        analysis?.title ?? fileName
    }

    private var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public var canToggleDisplayMode: Bool {
        availableModes.count > 1
    }

    /// 編集と閲覧を切り替える（⌘E）。編集に戻るときは、前に使っていた編集のモードにする。
    public func toggleDisplayMode() {
        guard canToggleDisplayMode else { return }
        displayMode = displayMode == .reading ? lastEditingMode : .reading
    }

    /// 本文を編集できるファイルか。読むだけでつないだフォルダ（~/Research など）の中は書き換えない。
    public var isEditable: Bool {
        kind.hasSourceView && !isReadOnly
    }

    /// 読むだけのファイルか。
    public let isReadOnly: Bool

    /// 今の中身と表示モードから、どう描くかを決める。本文は `text` から読む。
    public var display: DocumentDisplay {
        if let errorMessage { return .failed(message: errorMessage) }
        guard let document else { return .loading }
        switch (document.content, displayMode) {
        case (.markdown, .reading):
            return .markdownReading(vaultRoot: locateFile.vaultRoot())
        case (.markdown, let mode):
            return .markdownEditor(livePreview: mode == .livePreview)
        case (.html, .reading):
            return .htmlPage(vaultRoot: locateFile.vaultRoot())
        case (.html, _):
            return .codeEditor(language: "html")
        case (.text, _):
            if case .code(let language) = kind { return .codeEditor(language: language) }
            return .codeEditor(language: nil)
        case (.image(let url), _):
            return .image(url)
        case (.pdf(let url), _):
            return .pdf(url)
        case (.other(let url), _):
            return .quickLook(url)
        }
    }

    /// 保存していない編集があるか（タブに印を出す）。
    public var hasUnsavedChanges: Bool {
        guard let savedText else { return false }
        return storedText != savedText
    }

    // MARK: - インスペクタ

    public var fileInfo: FileInfoItem? {
        guard let info = document?.info else { return nil }
        return FileInfoItem(
            name: fileName,
            kind: FileIcon.displayName(for: kind),
            size: info.size.formatted(.byteCount(style: .file)),
            created: info.created?.formatted(date: .abbreviated, time: .shortened),
            modified: info.modified.formatted(date: .abbreviated, time: .shortened),
            location: path
        )
    }

    /// フロントマターのプロパティ（タイトルとタグはほかの場所に出すので除く）。
    public var properties: [PropertyItem] {
        analysis?.properties
            .filter { $0.key != "title" && $0.key != "tags" && $0.key != "tag" && !$0.value.displayString.isEmpty }
            .map { PropertyItem(key: $0.key, value: $0.value.displayString) } ?? []
    }

    public var tags: [String] {
        analysis?.tags ?? []
    }

    /// 目次（Markdown のとき）。
    public var outline: [OutlineItem] {
        guard let analysis else { return [] }
        return analysis.headings.enumerated().map { index, heading in
            OutlineItem(index: index, level: heading.level, title: heading.text, line: heading.line)
        }
    }

    /// バックリンクを出すか（ノートと HTML のときだけ）。
    public var showsBacklinks: Bool {
        kind == .markdown || kind == .html
    }

    /// Finder で表示するための、ファイルの場所。
    public var fileURL: URL {
        locateFile(path)
    }

    /// 指定の行へ移る（出典や知識グラフから開いたとき）。読み込む前なら、読み込んでから移る。
    public func reveal(line: Int) {
        pendingLine = line
        applyPendingLine()
    }

    private func applyPendingLine() {
        guard let line = pendingLine, document != nil else { return }
        pendingLine = nil
        let heading = outline.last { $0.line <= line }
        scrollTarget = OutlineItem(
            index: heading?.index ?? 0, level: heading?.level ?? 1, title: heading?.title ?? "", line: line)
    }

    // MARK: - 読み込み

    /// ファイルを読み直す。Vault が変わったときにも呼ぶ。
    ///
    /// 保存していない編集があるときは、画面の本文を残す（次の自動保存でファイルを上書きする）。
    public func load() async {
        do {
            let loaded = try await openDocument(path: path)
            document = loaded
            errorMessage = nil
            if let source = loaded.content.source, !hasUnsavedChanges {
                if source != storedText || savedText == nil {
                    storedText = source
                    revision += 1
                }
                savedText = source
                if case .markdown(_, let loadedAnalysis) = loaded.content { analysis = loadedAnalysis }
            }
        } catch {
            errorMessage = error.message
        }
        applyPendingLine()
        await loadBacklinks()
    }

    public func loadBacklinks() async {
        guard showsBacklinks else { return }
        backlinks = ((try? await findBacklinks(to: path)) ?? []).map(NoteLinkItem.init)
    }

    // MARK: - 保存

    private func didEdit() {
        saveState = .unsaved
        if kind == .markdown { analysis = analyzeNote(storedText, path: path) }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self, autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// 待たずに今すぐ保存する（タブを閉じるとき、アプリを終了するとき）。
    public func flush() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        await save()
    }

    /// 保存する。保存は 1 つずつ順に行う（古い本文があとから書かれないように）。
    private func save() async {
        let previous = saveInFlight
        let task = Task { [weak self] in
            await previous?.value
            await self?.writeIfNeeded()
        }
        saveInFlight = task
        await task.value
    }

    private func writeIfNeeded() async {
        guard isEditable, let savedText, storedText != savedText else {
            if case .failed = saveState {} else { saveState = .saved }
            return
        }
        let snapshot = storedText
        saveState = .saving
        do {
            try await saveDocument(snapshot, to: path)
            self.savedText = snapshot
            revision += 1
            saveState = storedText == snapshot ? .saved : .unsaved
        } catch {
            Self.logger.error("保存に失敗: \(self.path, privacy: .public) \(error.message, privacy: .public)")
            saveState = .failed(message: error.message)
        }
    }
}

/// 保存の状態。
public enum SaveState: Equatable, Sendable {
    case saved
    case unsaved
    case saving
    case failed(message: String)
}
