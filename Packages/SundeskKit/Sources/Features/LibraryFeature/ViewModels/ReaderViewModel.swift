//
//  ReaderViewModel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import CoreGraphics
import Foundation
import Observation
import SundeskDomain

/// PDF を読む画面の状態。ハイライトとコメントを持ち、メモと要約は ``ReferenceDetailViewModel`` に任せる。
@MainActor
@Observable
public final class ReaderViewModel {
    public let detail: ReferenceDetailViewModel
    public private(set) var title = ""
    public private(set) var pdfURL: URL?
    public private(set) var highlights: [HighlightDisplay] = []
    public var selectedHighlightID: UUID?
    /// 次に付けるハイライトの色。
    public var color = HighlightColor.yellow
    public var errorMessage: String?

    private var annotations: [Annotation] = []
    private var commentTasks: [UUID: Task<Void, Never>] = [:]
    private let referenceID: UUID
    private let library: any ManageLibraryUseCase

    public init(referenceID: UUID, library: any ManageLibraryUseCase, detail: ReferenceDetailViewModel) {
        self.referenceID = referenceID
        self.library = library
        self.detail = detail
    }

    public func start() async {
        await reload()
        for await _ in await library.changes() {
            await reload()
        }
    }

    public func addHighlight(text: String, rects: [HighlightRect]) async {
        guard !rects.isEmpty else { return }
        let annotation = Annotation(
            referenceID: referenceID, color: color.annotationColor, text: text,
            rects: rects.map {
                AnnotationRect(
                    pageIndex: $0.pageIndex, x: $0.rect.minX, y: $0.rect.minY, width: $0.rect.width,
                    height: $0.rect.height)
            })
        await save(annotation)
        selectedHighlightID = annotation.id
    }

    /// コメントを書き換える。打ち終わるのを少し待ってから保存する。
    public func setComment(_ comment: String, for id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].comment = comment
        highlights = annotations.map(HighlightDisplay.init)
        let annotation = annotations[index]
        commentTasks[id]?.cancel()
        commentTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commentTasks[id] = nil
            await save(annotation)
        }
    }

    public func setColor(_ color: HighlightColor, for id: UUID) async {
        guard var annotation = annotations.first(where: { $0.id == id }) else { return }
        annotation.color = color.annotationColor
        await save(annotation)
    }

    public func deleteHighlight(_ id: UUID) async {
        if selectedHighlightID == id { selectedHighlightID = nil }
        do {
            try await library.deleteAnnotation(id)
        } catch {
            errorMessage = error.message
        }
    }

    /// 選んだハイライトの文とコメントを、引用としてメモの末尾に書き足す。
    public func appendToNote(_ id: UUID) {
        guard let highlight = highlights.first(where: { $0.id == id }), detail.draft != nil else { return }
        let quote = highlight.text.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
        var block = "\(quote)\n> （\(highlight.pageLabel)）"
        if !highlight.comment.isEmpty { block += "\n\n\(highlight.comment)" }
        let note = detail.draft?.note ?? ""
        detail.draft?.note = (note.isEmpty ? "" : note + "\n\n") + block
    }

    public func attachPDF(_ url: URL) async {
        await detail.attachPDF(url)
    }

    private func save(_ annotation: Annotation) async {
        do {
            try await library.save(annotation)
        } catch {
            errorMessage = error.message
        }
    }

    private func reload() async {
        do {
            guard let reference = try await library.reference(referenceID) else { return }
            title = reference.metadata.title
            pdfURL = library.pdfURL(of: reference)
            annotations = try await library.annotations(of: referenceID)
        } catch {
            errorMessage = error.message
            return
        }
        // 打っている途中のコメントは、保存し終わるまで画面の値を残す
        for id in commentTasks.keys {
            guard let local = highlights.first(where: { $0.id == id }),
                let index = annotations.firstIndex(where: { $0.id == id })
            else { continue }
            annotations[index].comment = local.comment
        }
        highlights = annotations.map(HighlightDisplay.init)
    }
}
