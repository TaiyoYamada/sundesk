//
//  PDFReaderController.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import AppKit
import PDFKit

/// PDF を表示する PDFView と、その上のハイライトを扱う。ハイライトは PDF のファイルには保存しない。
@MainActor
final class PDFReaderController {
    let pdfView = PDFView()
    /// 描いているハイライトを押したとき。
    var onHitHighlight: ((UUID) -> Void)?

    private var loadedURL: URL?
    private var shown: [HighlightDisplay] = []
    private var hitObserver: (any NSObjectProtocol)?

    init() {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        hitObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewAnnotationHit, object: pdfView, queue: .main
        ) { [weak self] notification in
            let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFAnnotation
            guard let id = annotation?.userName.flatMap(UUID.init(uuidString:)) else { return }
            MainActor.assumeIsolated { self?.onHitHighlight?(id) }
        }
    }

    isolated deinit {
        if let hitObserver { NotificationCenter.default.removeObserver(hitObserver) }
    }

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        pdfView.document = PDFDocument(url: url)
        loadedURL = url
        shown = []
    }

    /// ハイライトを描き直す（変わったときだけ）。
    func show(_ highlights: [HighlightDisplay]) {
        guard highlights != shown, let document = pdfView.document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            // 自分で足したもの（userName に注釈の ID を入れている）だけを外す
            for annotation in page.annotations where annotation.userName.flatMap(UUID.init(uuidString:)) != nil {
                page.removeAnnotation(annotation)
            }
        }
        for highlight in highlights {
            for (pageIndex, rects) in Dictionary(grouping: highlight.rects, by: \.pageIndex) {
                guard let page = document.page(at: pageIndex) else { continue }
                page.addAnnotation(annotation(for: highlight, rects: rects.map(\.rect)))
            }
        }
        shown = highlights
    }

    /// 選んでいる文と、その範囲（行ごとの四角）。選んでいなければ nil。
    func takeSelection() -> (text: String, rects: [HighlightRect])? {
        guard let selection = pdfView.currentSelection, let document = pdfView.document,
            let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        let rects = selection.selectionsByLine().flatMap { line in
            line.pages.map { page in HighlightRect(pageIndex: document.index(for: page), rect: line.bounds(for: page)) }
        }
        pdfView.clearSelection()
        return (text, rects)
    }

    func reveal(_ highlight: HighlightDisplay) {
        guard let first = highlight.rects.first, let page = pdfView.document?.page(at: first.pageIndex) else { return }
        pdfView.go(to: first.rect.insetBy(dx: 0, dy: -40), on: page)
    }

    private func annotation(for highlight: HighlightDisplay, rects: [CGRect]) -> PDFAnnotation {
        let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.color = highlight.color.nsColor.withAlphaComponent(0.4)
        annotation.userName = highlight.id.uuidString
        // 四角ごとに、左上、右上、左下、右下の順で、bounds の左下からの位置を並べる
        annotation.quadrilateralPoints = rects.flatMap { rect in
            [
                CGPoint(x: rect.minX - bounds.minX, y: rect.maxY - bounds.minY),
                CGPoint(x: rect.maxX - bounds.minX, y: rect.maxY - bounds.minY),
                CGPoint(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY),
                CGPoint(x: rect.maxX - bounds.minX, y: rect.minY - bounds.minY),
            ].map { NSValue(point: $0) }
        }
        return annotation
    }
}
