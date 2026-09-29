//
//  InlineTextView.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskMarkdown
import SwiftUI

/// 段落や見出しの中身を、1 つの `Text` にして描く（文の途中で改行でき、選択もできる）。
struct InlineTextView: View {
    let inlines: [MarkdownInline]
    var fontSize: CGFloat = EditorTheme.bodySize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        var builder = InlineTextBuilder(fontSize: fontSize, isDark: colorScheme == .dark)
        builder.append(inlines)
        return builder.build()
            .font(.system(size: fontSize))
            .lineSpacing(fontSize * 0.3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// インラインの並びを `Text` に組み立てる。
///
/// 文字は `AttributedString` にまとめ、数式（SwiftMath の画像）のところだけ `Text(Image)` を挟む。
struct InlineTextBuilder {
    let fontSize: CGFloat
    let isDark: Bool
    private var parts: [Text] = []
    private var buffer = AttributedString()

    init(fontSize: CGFloat, isDark: Bool) {
        self.fontSize = fontSize
        self.isDark = isDark
    }

    mutating func append(_ inlines: [MarkdownInline], intent: InlinePresentationIntent = [], link: URL? = nil) {
        for inline in inlines {
            append(inline, intent: intent, link: link)
        }
    }

    private mutating func append(_ inline: MarkdownInline, intent: InlinePresentationIntent, link: URL?) {
        switch inline {
        case .text(let text):
            appendText(text, intent: intent, link: link)
        case .strong(let content):
            append(content, intent: intent.union(.stronglyEmphasized), link: link)
        case .emphasis(let content):
            append(content, intent: intent.union(.emphasized), link: link)
        case .strikethrough(let content):
            append(content, intent: intent.union(.strikethrough), link: link)
        case .code(let code):
            var text = AttributedString(code)
            text.inlinePresentationIntent = intent.union(.code)
            text.backgroundColor = Color(nsColor: EditorTheme.codeBackground)
            text.link = link
            buffer += text
        case .link(let target, let content):
            append(content, intent: intent, link: DocumentLink(target)?.url ?? link)
        case .wikilink(let target, let label):
            appendText(label, intent: intent, link: DocumentLink.note(target).url)
        case .math(let latex):
            appendMath(latex)
        case .tag(let name):
            var text = AttributedString("#" + name)
            text.link = DocumentLink.tag(name).url
            text.foregroundColor = Color(nsColor: EditorTheme.tagColor)
            buffer += text
        case .image(let image):
            appendText(
                "🖼 " + (image.alt.isEmpty ? "画像" : image.alt), intent: intent, link: DocumentLink(image.source)?.url)
        case .lineBreak, .softBreak:
            // Obsidian と同じく、改行はそのまま改行として見せる
            buffer += AttributedString("\n")
        }
    }

    private mutating func appendText(_ string: String, intent: InlinePresentationIntent, link: URL?) {
        var text = AttributedString(string)
        if !intent.isEmpty { text.inlinePresentationIntent = intent }
        text.link = link
        buffer += text
    }

    private mutating func appendMath(_ latex: String) {
        guard let rendered = MathRenderer.shared.render(latex, display: false, fontSize: fontSize, isDark: isDark)
        else {
            var text = AttributedString(latex)
            text.inlinePresentationIntent = .code
            text.foregroundColor = .red
            buffer += text
            return
        }
        flush()
        parts.append(Text(Image(nsImage: rendered.image)).baselineOffset(-rendered.descent))
    }

    private mutating func flush() {
        guard !buffer.characters.isEmpty else { return }
        parts.append(Text(buffer))
        buffer = AttributedString()
    }

    func build() -> Text {
        var builder = self
        builder.flush()
        guard let first = builder.parts.first else { return Text(verbatim: "") }
        return builder.parts.dropFirst().reduce(first) { Text("\($0)\($1)") }
    }
}
