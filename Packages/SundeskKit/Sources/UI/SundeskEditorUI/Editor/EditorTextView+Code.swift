//
//  EditorTextView+Code.swift
//  SundeskEditorUI
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit

extension EditorTextView {
    /// コードの編集の操作をする。本文を書き換えたら true。
    @discardableResult
    func perform(_ command: CodeCommand) -> Bool {
        guard let codeEditing, isEditable else { return false }
        let text = string
        let selection = selectedRange()
        let edit: CodeEdit? =
            switch command {
            case .toggleComment: codeEditing.toggleComment(in: text, selection: selection)
            case .duplicateLines: codeEditing.duplicateLines(in: text, selection: selection)
            case .moveLinesUp: codeEditing.moveLines(upward: true, in: text, selection: selection)
            case .moveLinesDown: codeEditing.moveLines(upward: false, in: text, selection: selection)
            case .indent: codeEditing.indentLines(in: text, selection: selection)
            case .dedent: codeEditing.dedent(in: text, selection: selection)
            }
        guard let edit else { return false }
        apply(edit)
        return true
    }

    /// 書き換えを、取り消せる形で本文に反映する。
    func apply(_ edit: CodeEdit) {
        if edit.movesOnly {
            setSelectedRange(edit.selection)
            return
        }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(
            in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    /// 右クリックのメニューの先頭に、コードの操作を足す。
    func addCodeItems(to menu: NSMenu) {
        let items = CodeCommand.allCases.map { command in
            let item = NSMenuItem(
                title: command.title, action: #selector(performCodeMenuItem(_:)), keyEquivalent: command.keyEquivalent)
            item.keyEquivalentModifierMask = command.modifiers
            item.representedObject = command
            item.target = self
            return item
        }
        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
        menu.insertItem(.separator(), at: items.count)
    }

    @objc private func performCodeMenuItem(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? CodeCommand else { return }
        perform(command)
    }
}

extension CodeCommand {
    /// キーの組み合わせから操作を選ぶ（⌘/、⌘D、⌥↑、⌥↓、⌘]、⌘[）。
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers
        switch modifiers {
        case .option where event.keyCode == 126: self = .moveLinesUp
        case .option where event.keyCode == 125: self = .moveLinesDown
        case .command where key == "/": self = .toggleComment
        case .command where key == "d": self = .duplicateLines
        case .command where key == "]": self = .indent
        case .command where key == "[": self = .dedent
        default: return nil
        }
    }

    /// メニューに出す名前。
    public var title: String {
        switch self {
        case .toggleComment: "コメントの切り替え"
        case .duplicateLines: "行を複製"
        case .moveLinesUp: "行を上へ"
        case .moveLinesDown: "行を下へ"
        case .indent: "インデントを増やす"
        case .dedent: "インデントを減らす"
        }
    }

    fileprivate var keyEquivalent: String {
        switch self {
        case .toggleComment: "/"
        case .duplicateLines: "d"
        case .moveLinesUp: String(Character(UnicodeScalar(UInt16(NSUpArrowFunctionKey)) ?? "↑"))
        case .moveLinesDown: String(Character(UnicodeScalar(UInt16(NSDownArrowFunctionKey)) ?? "↓"))
        case .indent: "]"
        case .dedent: "["
        }
    }

    fileprivate var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .moveLinesUp, .moveLinesDown: .option
        default: .command
        }
    }
}
