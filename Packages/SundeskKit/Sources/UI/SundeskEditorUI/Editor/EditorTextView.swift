//
//  EditorTextView.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit

/// TextKit 2 の NSTextView。リンクを開く、行番号を描く、行の長さを絞る、指定の行へ移る。
/// コードでは、今の行を強調し、自動インデントや括弧の補完などの編集をする（`codeEditing`）。
final class EditorTextView: NSTextView {
    /// リンクが押されたとき。
    var onOpenLink: ((DocumentLink) -> Void)?
    /// ⌘ なしのクリックでもリンクを開くか（ライブプレビューで、記号を隠しているリンク）。
    var opensLinkWithoutCommand: (NSRange) -> Bool = { _ in false }

    var showsLineNumbers = false {
        didSet { updateInsets() }
    }

    /// 1 行の長さを絞って、中央に寄せるか（Markdown）。
    var limitsLineLength = false {
        didSet { updateInsets() }
    }

    /// コードの編集（自動インデント、コメントの切り替えなど）。nil ならふつうのテキストとして編集する。
    var codeEditing: CodeEditing?

    /// カーソルのある行を強調するか（コード）。
    var highlightsCurrentLine = false {
        didSet { needsDisplay = true }
    }

    /// 各行の先頭の位置（UTF-16）。行番号と行への移動に使う。
    private var lineStarts: [Int] = [0]
    private static let gutterWidth: CGFloat = 44

    // MARK: - 設定

    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        smartInsertDeleteEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        setAccessibilityIdentifier("text-editor")
        updateInsets()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        var horizontal: CGFloat = showsLineNumbers ? Self.gutterWidth + 8 : 24
        if limitsLineLength {
            horizontal = max(horizontal, (bounds.width - EditorTheme.readableWidth) / 2)
        }
        let inset = NSSize(width: horizontal.rounded(), height: 20)
        if textContainerInset != inset { textContainerInset = inset }
    }

    // MARK: - 行

    override func didChangeText() {
        super.didChangeText()
        updateLineStarts()
        if showsLineNumbers { needsDisplay = true }
    }

    func updateLineStarts() {
        let string = self.string as NSString
        var starts = [0]
        var location = 0
        while location < string.length {
            let range = string.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            if location < string.length || (location == string.length && string.hasSuffix("\n")) {
                starts.append(location)
            }
            if range.length == 0 { break }
        }
        lineStarts = starts
    }

    /// 1 始まりの行番号の行へスクロールし、カーソルを置く。
    func scrollToLine(_ line: Int) {
        let location = lineStarts.indices.contains(line - 1) ? lineStarts[line - 1] : (string as NSString).length
        setSelectedRange(NSRange(location: location, length: 0))
        window?.makeFirstResponder(self)

        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
            let target = content.location(content.documentRange.location, offsetBy: location),
            let range = NSTextRange(location: content.documentRange.location, end: target)
        else {
            scrollRangeToVisible(NSRange(location: location, length: 0))
            return
        }
        layoutManager.ensureLayout(for: range)
        if let fragment = layoutManager.textLayoutFragment(for: target) {
            scroll(NSPoint(x: 0, y: max(fragment.layoutFragmentFrame.minY + textContainerOrigin.y - 12, 0)))
        } else {
            scrollRangeToVisible(NSRange(location: location, length: 0))
        }
    }

    // MARK: - 行番号

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let currentLine = highlightsCurrentLine ? currentLineRect() : nil
        if let currentLine {
            EditorTheme.currentLineColor.setFill()
            currentLine.intersection(rect).fill()
        }
        guard showsLineNumbers, let layoutManager = textLayoutManager, let content = layoutManager.textContentManager
        else { return }

        let origin = textContainerOrigin
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let start =
            layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(rect.minY - origin.y, 0)))?.rangeInElement
            .location
            ?? layoutManager.documentRange.location

        layoutManager.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + origin.y > rect.maxY { return false }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            guard let line = lineNumber(at: offset) else { return true }

            let number = "\(line)" as NSString
            let size = number.size(withAttributes: attributes)
            let lineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? size.height
            let point = NSPoint(
                x: origin.x - 12 - size.width,
                y: frame.minY + origin.y + (lineHeight - size.height) / 2
            )
            let isCurrent = currentLine.map { abs($0.minY - (frame.minY + origin.y)) < 1 } ?? false
            number.draw(at: point, withAttributes: isCurrent ? currentAttributes : attributes)
            return true
        }
    }

    /// カーソルのある行（折り返した行なら、その見た目の 1 行）の四角。文字を選んでいるときは nil。
    private func currentLineRect() -> NSRect? {
        let selection = selectedRange()
        guard selection.length == 0, let layoutManager = textLayoutManager,
            let content = layoutManager.textContentManager,
            let location = content.location(content.documentRange.location, offsetBy: selection.location)
        else { return nil }
        var lineFrame: CGRect?
        layoutManager.enumerateTextSegments(
            in: NSTextRange(location: location), type: .standard, options: [.rangeNotRequired]
        ) { _, frame, _, _ in
            lineFrame = frame
            return false
        }
        guard let lineFrame else { return nil }
        return NSRect(x: 0, y: lineFrame.minY + textContainerOrigin.y, width: bounds.width, height: lineFrame.height)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if highlightsCurrentLine { setNeedsDisplay(visibleRect) }
    }

    /// 行の先頭の位置から、1 始まりの行番号を探す。
    private func lineNumber(at offset: Int) -> Int? {
        var lower = 0
        var upper = lineStarts.count - 1
        while lower <= upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] == offset { return middle + 1 }
            if lineStarts[middle] < offset { lower = middle + 1 } else { upper = middle - 1 }
        }
        return nil
    }

    // MARK: - コードの編集

    /// コードの編集をするか。日本語の変換中は何もしない。
    private var editsCode: Bool { codeEditing != nil && isEditable && !hasMarkedText() }

    override func insertNewline(_ sender: Any?) {
        guard editsCode, let codeEditing else { return super.insertNewline(sender) }
        apply(codeEditing.newline(in: string, selection: selectedRange()))
    }

    override func insertTab(_ sender: Any?) {
        guard editsCode, let codeEditing else { return super.insertTab(sender) }
        apply(codeEditing.indent(in: string, selection: selectedRange()))
    }

    override func insertBacktab(_ sender: Any?) {
        guard editsCode else { return super.insertBacktab(sender) }
        perform(.dedent)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        guard editsCode, let codeEditing, replacementRange.location == NSNotFound, let text,
            let edit = codeEditing.insert(text, in: string, selection: selectedRange())
        else { return super.insertText(insertString, replacementRange: replacementRange) }
        apply(edit)
    }

    override func deleteBackward(_ sender: Any?) {
        guard editsCode, let codeEditing, let edit = codeEditing.deleteBackward(in: string, selection: selectedRange())
        else { return super.deleteBackward(sender) }
        apply(edit)
    }

    override func keyDown(with event: NSEvent) {
        if editsCode, let command = CodeCommand(event: event) {
            perform(command)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if editsCode, window?.firstResponder === self, let command = CodeCommand(event: event) {
            perform(command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard codeEditing != nil, isEditable, let menu else { return menu }
        addCodeItems(to: menu)
        return menu
    }

    /// 補完する語の範囲。コードでは、`_` と数字を含む識別子をひとまとまりにする。
    override var rangeForUserCompletion: NSRange {
        guard codeEditing != nil else { return super.rangeForUserCompletion }
        let selection = selectedRange()
        let string = self.string as NSString
        var start = selection.location
        while let previous = CodeEditing.character(in: string, at: start - 1), CodeEditing.isIdentifier(previous) {
            start -= 1
        }
        return NSRange(location: start, length: selection.location - start)
    }

    // MARK: - リンク

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let (link, range) = link(near: index),
            event.modifierFlags.contains(.command) || opensLinkWithoutCommand(range)
        {
            onOpenLink?(link)
            return
        }
        super.mouseDown(with: event)
    }

    private func link(near index: Int) -> (DocumentLink, NSRange)? {
        guard let storage = textStorage else { return nil }
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            var range = NSRange()
            if let attribute = storage.attribute(.documentLink, at: candidate, effectiveRange: &range) as? LinkAttribute
            {
                return (attribute.link, range)
            }
        }
        return nil
    }
}
