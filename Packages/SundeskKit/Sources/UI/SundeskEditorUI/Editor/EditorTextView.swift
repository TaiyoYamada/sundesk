//
//  EditorTextView.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit

/// TextKit 2 の NSTextView。リンクを開く、行の長さを絞る、指定の行へ移る。
final class EditorTextView: NSTextView {
    /// リンクが押されたとき。
    var onOpenLink: ((DocumentLink) -> Void)?
    /// ⌘ なしのクリックでもリンクを開くか（ライブプレビューで、記号を隠しているリンク）。
    var opensLinkWithoutCommand: (NSRange) -> Bool = { _ in false }

    /// 各行の先頭の位置（UTF-16）。行への移動に使う。
    private var lineStarts: [Int] = [0]

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

    /// 1 行の長さを絞って、中央に寄せる。
    private func updateInsets() {
        let horizontal = max(24, (bounds.width - EditorTheme.readableWidth) / 2)
        let inset = NSSize(width: horizontal.rounded(), height: 20)
        if textContainerInset != inset { textContainerInset = inset }
    }

    // MARK: - 行

    override func didChangeText() {
        super.didChangeText()
        updateLineStarts()
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
