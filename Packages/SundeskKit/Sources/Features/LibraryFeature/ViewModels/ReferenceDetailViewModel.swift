//
//  ReferenceDetailViewModel.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import Observation
import SundeskDomain

/// 1 件の文献の書誌情報、タグ、メモ、要約を編集する。編集は少し待ってから自動で保存する。
@MainActor
@Observable
public final class ReferenceDetailViewModel {
    public let referenceID: UUID
    public var draft: ReferenceDraft? {
        didSet {
            if !isApplyingStoredValue, draft != oldValue { scheduleSave() }
        }
    }
    public private(set) var hasPDF = false
    public private(set) var summary: SummaryDisplay?
    public private(set) var summaryState = SummaryState.idle
    public private(set) var isRefreshing = false
    public var errorMessage: String?

    private var stored: Reference?
    private var isApplyingStoredValue = false
    private var saveTask: Task<Void, Never>?
    private let library: any ManageLibraryUseCase
    private let summarize: any SummarizePaperUseCase

    public init(referenceID: UUID, library: any ManageLibraryUseCase, summarize: any SummarizePaperUseCase) {
        self.referenceID = referenceID
        self.library = library
        self.summarize = summarize
    }

    /// 読み込み、そのあとは変更を見張る。ほかのウインドウでの編集や、できあがった要約を取り込む。
    public func start() async {
        await reload()
        for await _ in await library.changes() {
            await reload()
        }
    }

    /// 待っている保存を、すぐに行う（画面を閉じるときなど）。
    public func flush() async {
        guard let saveTask else { return }
        saveTask.cancel()
        self.saveTask = nil
        await save()
    }

    public func addTag(_ text: String) {
        let tag = text.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, draft?.tags.contains(tag) == false else { return }
        draft?.tags.append(tag)
    }

    public func removeTag(_ tag: String) {
        draft?.tags.removeAll { $0 == tag }
    }

    public var pdfURL: URL? {
        stored.flatMap(library.pdfURL(of:))
    }

    public func attachPDF(_ url: URL) async {
        await flush()
        do {
            try await library.attachPDF(url, to: referenceID)
        } catch {
            errorMessage = error.message
        }
    }

    /// DOI、arXiv の ID、ISBN から書誌情報を引き直す。
    public func refreshMetadata() async {
        await flush()
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await library.refreshMetadata(of: referenceID)
        } catch {
            errorMessage = error.message
        }
    }

    public func makeSummary() async {
        await flush()
        summaryState = .running("PDF を読んでいます")
        do {
            for try await progress in summarize(referenceID) {
                switch progress {
                case .reading(let part, let count):
                    summaryState = .running("本文を読んでいます（\(part) / \(count)）")
                case .combining:
                    summaryState = .running("要約をまとめています")
                case .finished(let summary):
                    self.summary = SummaryDisplay(summary)
                    summaryState = .idle
                }
            }
        } catch let error as SummaryError {
            summaryState = .failed(error.message)
        } catch let error as LibraryError {
            summaryState = .failed(error.message)
        } catch {
            summaryState = .failed(error.localizedDescription)
        }
    }

    /// 要約をメモの末尾に書き足す。
    public func appendSummaryToNote() {
        guard let summary, draft != nil else { return }
        let note = draft?.note ?? ""
        draft?.note = (note.isEmpty ? "" : note + "\n\n") + "# 要約\n\n" + summary.markdown
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveTask = nil
            await save()
        }
    }

    private func save() async {
        guard var reference = stored, let draft else { return }
        draft.apply(to: &reference)
        do {
            try await library.save(reference)
            stored = reference
        } catch {
            errorMessage = error.message
        }
    }

    private func reload() async {
        let reference: Reference?
        do {
            reference = try await library.reference(referenceID)
        } catch {
            errorMessage = error.message
            return
        }
        guard let reference else {
            stored = nil
            setDraft(nil)
            return
        }
        hasPDF = reference.attachment != nil
        summary = reference.summary.map(SummaryDisplay.init)
        // 保存を待っている編集があるときは、画面の値を残す（保存すると、それが新しい値になる）
        guard saveTask == nil else { return }
        stored = reference
        setDraft(ReferenceDraft(reference))
    }

    private func setDraft(_ value: ReferenceDraft?) {
        isApplyingStoredValue = true
        draft = value
        isApplyingStoredValue = false
    }
}
