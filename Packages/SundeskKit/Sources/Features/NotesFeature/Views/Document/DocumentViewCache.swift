//
//  DocumentViewCache.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskEditorUI
import SundeskWebView

/// 開いているファイルごとのエディタと HTML のページ。
///
/// タブを切り替えても作り直さないので、取り消しの履歴、スクロール位置、選択が残る。
@MainActor
public final class DocumentViewCache {
    private var editors: [String: TextEditorSession] = [:]
    private var pages: [String: HTMLPage] = [:]

    public init() {}

    func editor(for path: String) -> TextEditorSession {
        if let editor = editors[path] { return editor }
        let editor = TextEditorSession()
        editors[path] = editor
        return editor
    }

    func page(for path: String) -> HTMLPage {
        if let page = pages[path] { return page }
        let page = HTMLPage()
        pages[path] = page
        return page
    }

    /// 閉じたタブの分を捨てる。
    public func keepOnly(paths: Set<String>) {
        editors = editors.filter { paths.contains($0.key) }
        pages = pages.filter { paths.contains($0.key) }
    }
}
