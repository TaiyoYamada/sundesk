//
//  ChatScreen.swift
//  ChatFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SwiftUI

/// チャットのタブ。左に会話の履歴、右に会話。
public struct ChatScreen: View {
    @Bindable private var viewModel: ChatViewModel
    private let openNote: (String, Int) -> Void
    @AppStorage("chat.model") private var storedModel = ""

    /// - Parameter openNote: 出典を押したとき（ノートのパス、行番号）。
    public init(viewModel: ChatViewModel, openNote: @escaping (String, Int) -> Void) {
        self.viewModel = viewModel
        self.openNote = openNote
    }

    public var body: some View {
        HStack(spacing: 0) {
            SessionListView(viewModel: viewModel)
                .frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if let build = viewModel.build {
                    ProgressBanner(title: build, fraction: nil)
                    Divider()
                }
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    Divider()
                }
                ConversationView(viewModel: viewModel, openNote: openNote)
                Divider()
                InputView(viewModel: viewModel)
            }
        }
        .task {
            if !storedModel.isEmpty { viewModel.selectedModelID = storedModel }
            await viewModel.loadModels()
        }
        .onChange(of: viewModel.selectedModelID) { _, id in storedModel = id }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("モデル", selection: $viewModel.selectedModelID) {
                ForEach(viewModel.models) { model in
                    Text(model.detail.map { "\(model.name)（\($0)）" } ?? model.name)
                        .tag(model.id)
                        .selectionDisabled(!model.isAvailable)
                }
            }
            .frame(maxWidth: 380)
            .accessibilityIdentifier("chat-model-picker")
            Button("モデルを読み直す", systemImage: "arrow.triangle.2.circlepath") {
                Task { await viewModel.loadModels() }
            }
            .labelStyle(.iconOnly)
            .help("手元のモデルを読み直す")
            Spacer()
            Button("知識を作り直す", systemImage: "books.vertical") { Task { await viewModel.rebuild() } }
                .help("ノートから、検索用の埋め込みと知識グラフを作り直す")
                .disabled(viewModel.build != nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// 会話の履歴。
private struct SessionListView: View {
    let viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会話").font(.headline)
                Spacer()
                Button("新しい会話", systemImage: "square.and.pencil") { viewModel.newSession() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("新しい会話（⇧⌘N）")
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            List(
                selection: Binding(
                    get: { viewModel.selectedSessionID },
                    set: { id in if let id { Task { await viewModel.select(sessionID: id) } } }
                )
            ) {
                ForEach(viewModel.sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).lineLimit(2)
                        Text(session.date).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("削除", role: .destructive) { Task { await viewModel.delete(sessionID: session.id) } }
                    }
                }
            }
            .listStyle(.sidebar)
            // タブの中ではサイドバーの素材を使わず、周りと同じ背景にする
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.sessions.isEmpty {
                    Text("まだ会話はありません").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 会話の中身。答えている途中の文章も出す。
private struct ConversationView: View {
    let viewModel: ChatViewModel
    let openNote: (String, Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if viewModel.messages.isEmpty && !viewModel.isAnswering {
                        ContentUnavailableView(
                            "ノートに聞いてみましょう", systemImage: "bubble.left.and.text.bubble.right",
                            description: Text("質問に関係するノートの節を探して、それを根拠に答えます。根拠は [1] のように番号で示します。")
                        )
                        .padding(.top, 60)
                    }
                    ForEach(viewModel.messages) { message in
                        MessageView(
                            role: message.role, content: message.content, citations: message.citations,
                            openNote: openNote)
                    }
                    if viewModel.isAnswering {
                        MessageView(
                            role: .assistant, content: viewModel.streamingAnswer,
                            citations: viewModel.streamingCitations, openNote: openNote, status: viewModel.status)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: viewModel.streamingAnswer) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: viewModel.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

private struct MessageView: View {
    let role: ChatMessageItem.Role
    let content: String
    let citations: [CitationItem]
    let openNote: (String, Int) -> Void
    var status: String?

    var body: some View {
        if role == .user {
            Text(content)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let status {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(status).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                if !content.isEmpty {
                    Text(AnswerText.attributed(content, citations: citations))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .environment(
                            \.openURL,
                            OpenURLAction { url in
                                if let number = AnswerText.citationNumber(from: url),
                                    let citation = citations.first(where: { $0.number == number })
                                {
                                    openNote(citation.path, citation.line)
                                    return .handled
                                }
                                return .systemAction
                            })
                }
                CitationChips(citations: citations, openNote: openNote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 出典の一覧。回答で番号を示したものを先に、残りは「ほかの候補」にまとめる。
private struct CitationChips: View {
    let citations: [CitationItem]
    let openNote: (String, Int) -> Void

    var body: some View {
        let cited = citations.filter(\.isCited)
        let others = citations.filter { !$0.isCited }
        VStack(alignment: .leading, spacing: 6) {
            if !cited.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(cited) { chip($0) }
                }
            }
            if !others.isEmpty {
                DisclosureGroup(cited.isEmpty ? "探した資料（\(others.count)）" : "ほかの候補（\(others.count)）") {
                    FlowLayout(spacing: 6) {
                        ForEach(others) { chip($0) }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }

    private func chip(_ citation: CitationItem) -> some View {
        Button {
            openNote(citation.path, citation.line)
        } label: {
            let place = citation.heading.isEmpty ? citation.title : "\(citation.title) › \(citation.heading)"
            Text("[\(citation.number)] \(place)")
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(citation.snippet)
    }
}

/// 質問の入力欄。⌘↩ で送る（日本語の変換の確定と区別するため、↩ だけでは送らない）。
private struct InputView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("ノートについて質問する", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .padding(8)
                .background(.background, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .accessibilityIdentifier("chat-input")
            if viewModel.isAnswering {
                Button("止める", systemImage: "stop.fill") { viewModel.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button("送る", systemImage: "arrow.up") { viewModel.send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!viewModel.canSend)
                    .buttonStyle(.borderedProminent)
            }
        }
        .labelStyle(.iconOnly)
        .padding(12)
    }
}

/// 回答の文章を整える。Markdown のインラインの書式を生かし、`[1]` を出典へのリンクにする。
enum AnswerText {
    private static let scheme = "sundesk-cite"

    static func attributed(_ content: String, citations: [CitationItem]) -> AttributedString {
        let numbers = Set(citations.map(\.number))
        let linked = content.replacing(/\[(\d{1,2})\]/) { match in
            guard let number = Int(match.output.1), numbers.contains(number) else { return String(match.output.0) }
            return "[[\(number)]](\(scheme)://\(number))"
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: linked, options: options)) ?? AttributedString(content)
    }

    static func citationNumber(from url: URL) -> Int? {
        guard url.scheme == scheme else { return nil }
        return url.host().flatMap(Int.init)
    }
}
