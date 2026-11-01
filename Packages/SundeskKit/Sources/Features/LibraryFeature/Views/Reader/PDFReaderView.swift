//
//  PDFReaderView.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import PDFKit
import SwiftUI

/// PDF を表示する。PDFView は ``PDFReaderController`` が持つ。
struct PDFReaderView: NSViewRepresentable {
    let url: URL
    let highlights: [HighlightDisplay]
    let controller: PDFReaderController

    func makeNSView(context: Context) -> PDFView {
        controller.pdfView
    }

    func updateNSView(_ view: PDFView, context: Context) {
        controller.load(url)
        controller.show(highlights)
    }
}
