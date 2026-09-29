import Foundation
import Observation

nonisolated struct TagCount: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let count: Int
}

enum VaultError: LocalizedError {
    case noVault
    case noteNotFound(String)
    case alreadyExists(String)
    case invalidName

    var errorDescription: String? {
        switch self {
        case .noVault: "Vault が開かれていません。"
        case .noteNotFound(let id): "ノートが見つかりません: \(id)"
        case .alreadyExists(let name): "同じ名前のノートが既にあります: \(name)"
        case .invalidName: "ノート名が空です。"
        }
    }
}

/// Vault（Markdown ファイルの入ったフォルダ）を読み書きし、検索用の索引を持つ。
///
/// ディスク上のファイルが正で、このストアはそのキャッシュにすぎない。
/// 外部での変更は `DirectoryWatcher` 経由で取り込む。
@Observable
final class VaultStore {
    private(set) var rootURL: URL?
    private(set) var notesByID: [String: Note] = [:]
    private(set) var isLoading = false

    // 以下は notesByID から導出する索引。rebuildIndex() でまとめて作り直す。
    /// 更新日時の新しい順。
    private(set) var allNotes: [Note] = []
    private(set) var tags: [TagCount] = []
    /// フロントマターの `type` の値の一覧。
    private(set) var collections: [String] = []
    private(set) var folders: [String] = []
    @ObservationIgnored private var titleIndex: [String: String] = [:]
    @ObservationIgnored private var backlinkIndex: [String: [String]] = [:]

    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let dailyFolder = "Daily"
    private static let vaultPathKey = "vaultPath"

    var vaultName: String { rootURL?.lastPathComponent ?? "" }

    // MARK: - 開く・閉じる

    /// 前回開いていた Vault があれば開き直す。
    func restoreLastVault() async {
        guard rootURL == nil,
              let path = UserDefaults.standard.string(forKey: Self.vaultPathKey) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        try? await open(URL(filePath: path, directoryHint: .isDirectory))
    }

    func open(_ url: URL) async throws {
        let root = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        watcher?.stop()
        rootURL = root
        notesByID = [:]
        rebuildIndex()
        UserDefaults.standard.set(root.path, forKey: Self.vaultPathKey)

        isLoading = true
        let result = await Self.scan(root: root, known: [:])
        isLoading = false
        guard rootURL == root else { return }
        apply(result)

        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        rootURL = nil
        notesByID = [:]
        rebuildIndex()
        UserDefaults.standard.removeObject(forKey: Self.vaultPathKey)
    }

    /// ディスクの状態を読み直す。変更のあったファイルだけを読み込む。
    func refresh() async {
        guard let root = rootURL else { return }
        let known = notesByID.mapValues(\.modified)
        let result = await Self.scan(root: root, known: known)
        guard rootURL == root else { return }
        apply(result)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: - 参照

    func note(_ id: String) -> Note? { notesByID[id] }

    /// `[[リンク]]` の参照先を探す。`フォルダ/名前` 形式にも対応する。
    func resolve(link: String) -> Note? {
        var target = link.trimmingCharacters(in: .whitespaces)
        if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
        if target.contains("/"), let note = notesByID[target + ".md"] { return note }
        let name = (target as NSString).lastPathComponent.lowercased()
        return titleIndex[name].flatMap { notesByID[$0] }
    }

    func backlinks(to id: String) -> [Note] {
        (backlinkIndex[id] ?? []).compactMap { notesByID[$0] }.sorted { $0.title < $1.title }
    }

    func notes(ofType type: String) -> [Note] {
        allNotes.filter { $0.type?.caseInsensitiveCompare(type) == .orderedSame }
    }

    /// タグで絞り込む。`a` を指定すると `a/b` のような下位タグも含む。
    func notes(tagged tag: String) -> [Note] {
        let tag = tag.lowercased()
        return allNotes.filter { note in
            note.tags.contains { $0.lowercased() == tag || $0.lowercased().hasPrefix(tag + "/") }
        }
    }

    func notes(inFolder folder: String) -> [Note] {
        allNotes.filter { $0.folder == folder || $0.folder.hasPrefix(folder + "/") }
    }

    func search(_ query: String) -> [SearchHit] {
        SearchEngine.search(query, in: allNotes)
    }

    // MARK: - 書き込み

    func save(_ id: String, content: String) throws {
        guard let root = rootURL else { throw VaultError.noVault }
        guard var note = notesByID[id] else { throw VaultError.noteNotFound(id) }
        guard note.content != content else { return }

        let url = root.appending(path: id)
        try content.write(to: url, atomically: true, encoding: .utf8)
        note.setContent(content)
        note.modified = Self.modificationDate(of: url) ?? .now
        notesByID[id] = note
        rebuildIndex()
    }

    @discardableResult
    func createNote(title: String, in folder: String = "", content: String? = nil) throws -> Note {
        guard let root = rootURL else { throw VaultError.noVault }
        let name = Self.sanitize(title)
        guard !name.isEmpty else { throw VaultError.invalidName }

        let id = uniqueID(folder: folder, name: name)
        let url = root.appending(path: id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = content ?? ""
        try text.write(to: url, atomically: true, encoding: .utf8)

        let note = Note(id: id, content: text, modified: Self.modificationDate(of: url) ?? .now)
        notesByID[id] = note
        rebuildIndex()
        return note
    }

    /// ゴミ箱へ移す（完全には消さない）。
    func delete(_ id: String) throws {
        guard let root = rootURL else { throw VaultError.noVault }
        try FileManager.default.trashItem(at: root.appending(path: id), resultingItemURL: nil)
        notesByID[id] = nil
        rebuildIndex()
    }

    /// 名前を変え、他のノートからの `[[旧名]]` も張り替える。新しい ID を返す。
    @discardableResult
    func rename(_ id: String, to newTitle: String) throws -> String {
        guard let root = rootURL else { throw VaultError.noVault }
        guard let note = notesByID[id] else { throw VaultError.noteNotFound(id) }
        let name = Self.sanitize(newTitle)
        guard !name.isEmpty else { throw VaultError.invalidName }
        guard name != note.title else { return id }

        let newID = note.folder.isEmpty ? "\(name).md" : "\(note.folder)/\(name).md"
        let caseOnlyChange = newID.lowercased() == id.lowercased()
        if notesByID[newID] != nil, !caseOnlyChange { throw VaultError.alreadyExists(name) }

        try FileManager.default.moveItem(at: root.appending(path: id), to: root.appending(path: newID))
        let referrers = backlinks(to: id).map(\.id)

        notesByID[id] = nil
        notesByID[newID] = Note(id: newID, content: note.content, modified: note.modified)
        rebuildIndex()

        for referrer in referrers where referrer != id {
            guard let other = notesByID[referrer] else { continue }
            let updated = Self.replacingLinks(in: other.content, from: note.title, to: name)
            try save(referrer, content: updated)
        }
        return newID
    }

    /// フロントマターの 1 項目を書き換える。`nil` で削除。
    func setProperty(_ key: String, to value: Frontmatter.Value?, in id: String) throws {
        guard let note = notesByID[id] else { throw VaultError.noteNotFound(id) }
        var frontmatter = note.frontmatter
        frontmatter[key] = value
        try save(id, content: Frontmatter.compose(frontmatter, body: note.body))
    }

    /// 指定した日のデイリーノートを返す。無ければ作る。
    func dailyNote(for date: Date = .now) throws -> Note {
        let name = date.formatted(.iso8601.year().month().day())
        if let existing = notesByID["\(Self.dailyFolder)/\(name).md"] { return existing }
        let heading = date.formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "ja_JP")))
        return try createNote(title: name, in: Self.dailyFolder, content: "# \(heading)\n\n")
    }

    // MARK: - 内部

    private func uniqueID(folder: String, name: String) -> String {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var candidate = "\(prefix)\(name).md"
        var n = 1
        let existing = Set(notesByID.keys.map { $0.lowercased() })
        while existing.contains(candidate.lowercased())
                || rootURL.map({ FileManager.default.fileExists(atPath: $0.appending(path: candidate).path) }) == true {
            candidate = "\(prefix)\(name) \(n).md"
            n += 1
        }
        return candidate
    }

    private func apply(_ result: ScanResult) {
        var notes = notesByID.filter { result.present.contains($0.key) }
        for note in result.changed {
            // 走査中に自分で保存した場合、古い内容で上書きしない
            if let current = notes[note.id], current.modified > note.modified { continue }
            notes[note.id] = note
        }
        guard notes != notesByID else { return }
        notesByID = notes
        rebuildIndex()
    }

    private func rebuildIndex() {
        allNotes = notesByID.values.sorted {
            $0.modified != $1.modified ? $0.modified > $1.modified : $0.id < $1.id
        }

        var titles: [String: String] = [:]
        // 同名ノートが複数あるときは、パスの短い方（ルートに近い方）を優先する
        for note in allNotes.sorted(by: { $0.id.count > $1.id.count }) {
            titles[note.title.lowercased()] = note.id
        }
        titleIndex = titles

        var backlinks: [String: [String]] = [:]
        var tagCounts: [String: (name: String, count: Int)] = [:]
        var types: [String: String] = [:]
        var folderSet = Set<String>()

        for note in allNotes {
            for link in note.links {
                guard let target = resolve(link: link), target.id != note.id else { continue }
                backlinks[target.id, default: []].append(note.id)
            }
            for tag in note.tags {
                tagCounts[tag.lowercased(), default: (tag, 0)].count += 1
            }
            if let type = note.type, !type.isEmpty {
                types[type.lowercased()] = types[type.lowercased()] ?? type
            }
            var folder = note.folder
            while !folder.isEmpty {
                folderSet.insert(folder)
                folder = (folder as NSString).deletingLastPathComponent
            }
        }

        backlinkIndex = backlinks
        tags = tagCounts.values
            .map { TagCount(name: $0.name, count: $0.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        collections = types.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        folders = folderSet.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - ファイル走査

    nonisolated struct ScanResult: Sendable {
        /// ディスク上に存在するノートの ID。
        var present: Set<String>
        /// 新しく読み込んだ（または変更のあった）ノート。
        var changed: [Note]
    }

    /// `known` と更新日時が異なるファイルだけを読み込む。
    @concurrent
    nonisolated static func scan(root: URL, known: [String: Date]) async -> ScanResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ScanResult(present: [], changed: []) }

        let rootComponents = root.pathComponents.count
        var present = Set<String>()
        var changed: [Note] = []

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let id = url.pathComponents.dropFirst(rootComponents).joined(separator: "/")
            guard let modified = modificationDate(of: url) else { continue }
            present.insert(id)
            if known[id] == modified { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            changed.append(Note(id: id, content: content, modified: modified))
        }
        return ScanResult(present: present, changed: changed)
    }

    nonisolated static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// ファイル名に使えない文字を置き換える。
    nonisolated static func sanitize(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        return title.components(separatedBy: forbidden).joined(separator: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// `[[old]]` `[[old|別名]]` `[[old#見出し]]` の `old` を `new` に置き換える。
    nonisolated static func replacingLinks(in content: String, from old: String, to new: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: old)
        guard let regex = try? NSRegularExpression(
            pattern: #"(!?\[\[)(?:[^\]\|#\^\n]*/)?"# + escaped + #"(?=\s*[\]\|#\^])"#,
            options: [.caseInsensitive]
        ) else { return content }
        let template = "$1" + NSRegularExpression.escapedTemplate(for: new)
        return regex.stringByReplacingMatches(
            in: content, range: NSRange(content.startIndex..., in: content), withTemplate: template
        )
    }
}
