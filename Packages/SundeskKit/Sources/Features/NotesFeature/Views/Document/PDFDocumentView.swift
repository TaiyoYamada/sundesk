//
//  PDFDocumentView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import PDFKit
import SwiftUI

/// PDF を PDFKit で表示する（プレビュー.app と同じ部品）。
struct PDFDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
