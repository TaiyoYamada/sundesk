//
//  TextEditorSessionTests.swift
//  SundeskEditorUITests
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import Foundation
import SundeskCodeHighlight
import Testing

@testable import SundeskEditorUI

@MainActor
@Suite("TextEditorSession")
struct TextEditorSessionTests {
    /// 範囲の文字が隠れているか（ライブプレビューで記号を隠すときの属性）。
    private func isHidden(_ session: TextEditorSession, _ substring: String, occurrence: Int = 0) -> Bool {
        let string = session.string as NSString
        var range = NSRange(location: 0, length: string.length)
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            found = string.range(of: substring, range: range)
            range = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
        }
        let font = session.textView.textStorage?.attribute(.font, at: found.location, effectiveRange: nil) as? NSFont
        return (font?.pointSize ?? 0) < 1
    }

    @Test("ライブプレビューでは、カーソルのない行の記号を隠す")
    func hidesSyntaxAwayFromCursor() {
        let session = TextEditorSession()
        session.update(text: "## 見出し\n\n**太字** と [[量子ビット]]", syntax: .markdown(livePreview: true, notePath: "a.md"))
        session.textView.setSelectedRange(NSRange(location: 0, length: 0))

        #expect(!isHidden(session, "## "))
        #expect(isHidden(session, "**"))
        #expect(isHidden(session, "[["))
        #expect(!isHidden(session, "量子ビット"))
    }

    @Test("カーソルを動かすと、その行の記号が見える")
    func revealsSyntaxOnCursorLine() {
        let session = TextEditorSession()
        let text = "## 見出し\n\n**太字**"
        session.update(text: text, syntax: .markdown(livePreview: true, notePath: "a.md"))

        session.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        #expect(isHidden(session, "## "))
        #expect(!isHidden(session, "**"))
    }

    @Test("ソースモードでは何も隠さない")
    func sourceModeShowsEverything() {
        let session = TextEditorSession()
        session.update(text: "## 見出し\n\n**太字**", syntax: .markdown(livePreview: false, notePath: "a.md"))

        #expect(!isHidden(session, "## "))
        #expect(!isHidden(session, "**"))
    }

    @Test("見出しは大きく、コードは等幅で色づけする")
    func stylesHeadingsAndCode() throws {
        let session = TextEditorSession()
        session.update(text: "# 題\n\n```swift\nlet a = 1\n```", syntax: .markdown(livePreview: false, notePath: "a.md"))
        let storage = try #require(session.textView.textStorage)
        let string = storage.string as NSString

        let heading = storage.attribute(.font, at: string.range(of: "題").location, effectiveRange: nil) as? NSFont
        #expect(heading?.pointSize == EditorTheme.headingSize(level: 1))

        let keyword = string.range(of: "let").location
        let codeFont = storage.attribute(.font, at: keyword, effectiveRange: nil) as? NSFont
        #expect(codeFont?.isFixedPitch == true)
        let color = storage.attribute(.foregroundColor, at: keyword, effectiveRange: nil) as? NSColor
        #expect(color == EditorTheme.color(for: .keyword))
    }

    @Test("編集すると本文を知らせる。外から本文が変わったら差し替える")
    func textChanges() {
        let session = TextEditorSession()
        var received: [String] = []
        session.onTextChange = { received.append($0) }
        session.update(text: "a", syntax: .markdown(livePreview: false, notePath: "a.md"))

        session.textView.setSelectedRange(NSRange(location: 1, length: 0))
        session.textView.insertText("b", replacementRange: session.textView.selectedRange())
        #expect(received == ["ab"])

        session.update(text: "外で変更", syntax: .markdown(livePreview: false, notePath: "a.md"))
        #expect(session.string == "外で変更")
    }

    @Test("リンクの属性に行き先を載せる")
    func linkAttributes() throws {
        let session = TextEditorSession()
        session.update(text: "[[量子ビット]] #線形代数", syntax: .markdown(livePreview: true, notePath: "a.md"))
        let storage = try #require(session.textView.textStorage)
        let string = storage.string as NSString

        let wikilink = storage.attribute(.documentLink, at: string.range(of: "量子").location, effectiveRange: nil)
        #expect((wikilink as? LinkAttribute)?.link == .note("量子ビット"))
        let tag = storage.attribute(.documentLink, at: string.range(of: "線形").location, effectiveRange: nil)
        #expect((tag as? LinkAttribute)?.link == .tag("線形代数"))
    }
}
