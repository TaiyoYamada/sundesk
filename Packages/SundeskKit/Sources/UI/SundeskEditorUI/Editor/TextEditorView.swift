//
//  TextEditorView.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskMarkdown
import SwiftUI

/// ノートやコードを編集するエディタ（TextKit 2 の NSTextView）。
///
/// Markdown はライブプレビュー（カーソルのない行の記号を隠す）とソース、コードは tree-sitter で色づけして行番号を出す。
/// 取り消し（⌘Z）と検索（⌘F）は NSTextView のものを使う。
/// エディタの本体は `TextEditorSession` が持つので、タブを切り替えても取り消しの履歴とスクロール位置が残る。
public struct TextEditorView: NSViewRepresentable {
    private let session: TextEditorSession
    @Binding private var text: String
    private let syntax: EditorSyntax
    @Binding private var scrollToLine: Int?
    private let onOpen: (DocumentLink) -> Void

    /// - Parameters:
    ///   - session: このファイルのエディタ（ファイルごとに 1 つ作って使い回す）。
    ///   - scrollToLine: 移る行（1 始まり）。移ったら nil に戻す。
    ///   - onOpen: リンクが押されたとき（⌘ クリック、ライブプレビューでは隠れたリンクのクリック）。
    public init(
        session: TextEditorSession,
        text: Binding<String>,
        syntax: EditorSyntax,
        scrollToLine: Binding<Int?>,
        onOpen: @escaping (DocumentLink) -> Void
    ) {
        self.session = session
        self._text = text
        self.syntax = syntax
        self._scrollToLine = scrollToLine
        self.onOpen = onOpen
    }

    public func makeNSView(context: Context) -> NSScrollView {
        update(session)
        return session.scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        update(session)
        if let line = scrollToLine {
            Task { @MainActor in
                session.textView.scrollToLine(line)
                scrollToLine = nil
            }
        }
    }

    private func update(_ session: TextEditorSession) {
        let binding = $text
        session.onTextChange = { binding.wrappedValue = $0 }
        session.onOpen = onOpen
        session.update(text: text, syntax: syntax)
    }
}

/// 1 つのファイルのエディタ。NSTextView と、その色づけの状態を持つ。
public final class TextEditorSession: NSObject, NSTextViewDelegate {
    let textView: EditorTextView
    let scrollView: NSScrollView
    var onTextChange: ((String) -> Void)?
    var onOpen: ((DocumentLink) -> Void)?

    private var syntax: EditorSyntax?
    /// 解析した記法の範囲。本文が変わるまで使い回す。
    private var spans: [MarkdownSyntaxSpan]?
    /// ライブプレビューで記号を見せている段落。
    private var revealed: NSRange?

    override public init() {
        textView = EditorTextView(usingTextLayoutManager: true)
        textView.configure()
        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        super.init()
        textView.delegate = self
        textView.onOpenLink = { [weak self] in self?.onOpen?($0) }
        textView.opensLinkWithoutCommand = { [weak self] range in
            guard let self, syntax?.livePreview == true else { return false }
            return MarkdownStyler(livePreview: true, revealed: revealed).hides(range)
        }
    }

    /// 今の本文（テスト用）。
    var string: String { textView.string }

    func update(text: String, syntax: EditorSyntax) {
        if self.syntax != syntax {
            self.syntax = syntax
            spans = nil
            textView.showsLineNumbers = if case .code = syntax { true } else { false }
            textView.limitsLineLength = syntax.isMarkdown
            revealed = currentParagraph()
            restyle()
            textView.needsDisplay = true
        }
        // 初めて開いたときや、ファイルが外で書き換えられたとき
        if textView.string != text, !textView.hasMarkedText() {
            replaceText(with: text)
        }
    }

    private func replaceText(with text: String) {
        let selection = textView.selectedRange()
        textView.string = text
        textView.updateLineStarts()
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        spans = nil
        restyle()
    }

    // MARK: - NSTextViewDelegate

    public func textDidChange(_ notification: Notification) {
        // 日本語の変換中（下線のついた未確定の文字）は触らない。確定したときにもう一度呼ばれる
        guard !textView.hasMarkedText() else { return }
        spans = nil
        revealed = currentParagraph()
        restyle()
        onTextChange?(textView.string)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard syntax?.livePreview == true, !textView.hasMarkedText() else { return }
        let paragraph = currentParagraph()
        guard paragraph != revealed else { return }
        revealed = paragraph
        restyle()
    }

    // MARK: - 色づけ

    private func currentParagraph() -> NSRange? {
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.location <= string.length else { return nil }
        return string.paragraphRange(for: selection)
    }

    private func restyle() {
        guard let storage = textView.textStorage, let syntax else { return }
        storage.beginEditing()
        switch syntax {
        case .markdown(let livePreview, let notePath):
            let spans = self.spans ?? MarkdownSyntax.spans(in: textView.string, notePath: notePath)
            self.spans = spans
            MarkdownStyler(livePreview: livePreview, revealed: revealed).apply(spans, to: storage)
            textView.typingAttributes = MarkdownStyler.baseAttributes
        case .code(let language):
            CodeStyler.apply(language: language, to: storage)
            textView.typingAttributes = CodeStyler.baseAttributes
        case .plain:
            CodeStyler.apply(language: nil, to: storage)
            textView.typingAttributes = CodeStyler.baseAttributes
        }
        storage.endEditing()
    }
}
