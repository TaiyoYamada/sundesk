//
//  RenderedPageCache.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import Observation
import SundeskComposition
import SundeskRenderer

/// 開いているファイルごとの WebKit のページ。タブを切り替えても描き直さず、スクロール位置も残す。
/// インスペクタの目次も、ここから読む。
@MainActor
@Observable
final class RenderedPageCache {
    private var pages: [String: RenderedPage] = [:]

    func page(for path: String) -> RenderedPage {
        if let page = pages[path] { return page }
        let page = RenderedPage(vaultRoot: { VaultSettings.directory() })
        pages[path] = page
        return page
    }

    func existingPage(for path: String) -> RenderedPage? {
        pages[path]
    }

    /// 閉じたタブのページを捨てる。
    func keepOnly(paths: Set<String>) {
        pages = pages.filter { paths.contains($0.key) }
    }
}
