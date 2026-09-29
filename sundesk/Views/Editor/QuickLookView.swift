//
//  QuickLookView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import QuickLookUI
import SwiftUI

/// その他のファイルを Quick Look でプレビューする（Finder でスペースキーを押したときと同じ）。
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }
}
