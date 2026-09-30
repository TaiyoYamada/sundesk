//
//  GraphScreen.swift
//  GraphFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SundeskGraphRenderer
import SwiftUI

/// 知識グラフのタブ。
///
/// 遠くからはまとまりの雲と名前、近づくと概念の名前、さらに近づくと選んだ概念が出てくるノートを見せる。
/// 検索して選ぶとカメラが飛び、⇧ を押しながら別の概念を押すと経路が光る。奥行き（3D）と、育つ様子の再生もできる。
public struct GraphScreen: View {
    @Bindable private var viewModel: GraphViewModel
    @AppStorage("graph.depth") private var prefersDepth = false
    @FocusState private var isSearchFocused: Bool
    @State private var suggestionIndex = 0
    private let openNote: ((String, Int) -> Void)?

    /// - Parameter openNote: ノートを開く（パス、行番号）。nil ならインスペクタが渡したものを使う。
    public init(viewModel: GraphViewModel, openNote: ((String, Int) -> Void)? = nil) {
        self.viewModel = viewModel
        self.openNote = openNote
    }

    private var canvas: GraphCanvasModel { viewModel.canvas }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let build = viewModel.build {
                ProgressBanner(title: build.title, fraction: build.fraction)
                Divider()
            }
            if let error = viewModel.buildError {
                ErrorBanner(message: error) { viewModel.buildError = nil }
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { shortcuts }
        .onAppear(perform: connect)
        .onChange(of: viewModel.nodes, initial: true) { applyScene() }
        .onChange(of: viewModel.edges) { applyScene() }
        .onChange(of: viewModel.communities) { applyScene() }
        .onChange(of: viewModel.matchingNodeIDs, initial: true) { _, ids in canvas.highlightedNodeIDs = ids }
        .onChange(of: viewModel.selected?.id) { _, id in canvas.select(nodeID: id) }
        .onChange(of: viewModel.path) { _, path in canvas.setPath(path.map(\.id)) }
        .onChange(of: viewModel.searchText) { suggestionIndex = 0 }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .empty:
            ContentUnavailableView {
                Label("知識グラフはまだありません", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text("ノートから用語と関係を抜き出して、グラフを作ります。初回はエンジンの準備とモデルのダウンロードに時間がかかります。")
            } actions: {
                Button("ノートから作る") { Task { await viewModel.rebuild() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.build != nil)
            }
        case .ready:
            GraphCanvasArea(
                viewModel: viewModel, canvas: canvas, suggestionIndex: suggestionIndex,
                showsSuggestions: isSearchFocused, choose: choose)
        case .failed(let message):
            ContentUnavailableView(
                "知識グラフを読めませんでした", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            searchField
            Picker("表示する概念", selection: $viewModel.nodeLimit) {
                ForEach(GraphViewModel.nodeLimits, id: \.self) { Text("上位 \($0)").tag($0) }
            }
            .fixedSize()
            Text(viewModel.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Picker("見え方", selection: depthBinding) {
                Text("2D").tag(false)
                Text("3D").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("奥行きをつけて、回して眺める（3D ではドラッグで回転、⌥ ドラッグで移動）")
            Button("育つ様子を再生", systemImage: "play.circle") { canvas.playTimeline() }
                .help("ノートを作った順に、知識が育つ様子を再生する")
                .disabled(viewModel.timeline.isEmpty || !canvas.hasTimeline)
            Button("全体を表示", systemImage: "arrow.up.left.and.arrow.down.right") { canvas.fitAll() }
                .help("全体を表示（空いているところをダブルクリック）")
            Button("配置し直す", systemImage: "wind") { canvas.reheat() }
                .help("点の配置をもう一度計算する")
            Button("作り直す", systemImage: "arrow.clockwise") { Task { await viewModel.rebuild() } }
                .help("ノートから知識グラフを作り直す")
                .disabled(viewModel.build != nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        TextField("概念を探す（⌘F）", text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            .focused($isSearchFocused)
            .onSubmit {
                let suggestions = viewModel.searchSuggestions
                if suggestions.indices.contains(suggestionIndex) { choose(suggestions[suggestionIndex].id) }
            }
            .onKeyPress(.downArrow) {
                suggestionIndex = min(suggestionIndex + 1, max(viewModel.searchSuggestions.count - 1, 0))
                return .handled
            }
            .onKeyPress(.upArrow) {
                suggestionIndex = max(suggestionIndex - 1, 0)
                return .handled
            }
            .onKeyPress(.escape) {
                viewModel.searchText = ""
                isSearchFocused = false
                canvas.focusKeyboard()
                return .handled
            }
    }

    /// 見えないボタンで、キーボードの近道を受ける。
    private var shortcuts: some View {
        Button("概念を探す") { isSearchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
    }

    private var depthBinding: Binding<Bool> {
        Binding(
            get: { canvas.is3D },
            set: { value in
                prefersDepth = value
                canvas.setDepth(value)
            })
    }

    /// 検索の候補を選んだ: カメラを飛ばして選ぶ。
    private func choose(_ id: Int) {
        viewModel.searchText = ""
        isSearchFocused = false
        canvas.fly(toNode: id)
        canvas.focusKeyboard()
        Task { await viewModel.select(conceptID: id) }
    }

    private func connect() {
        canvas.onSelect = { id in Task { await viewModel.select(conceptID: id) } }
        canvas.onOpen = { id in Task { await viewModel.openSource(of: id) } }
        canvas.onPathTarget = { id in
            if let id { viewModel.findPath(to: id) } else { viewModel.clearPath() }
        }
        if let openNote { viewModel.noteOpener = openNote }
        canvas.setDepth(prefersDepth)
    }

    private func applyScene() {
        canvas.setScene(
            GraphScene(
                nodes: viewModel.nodes.map {
                    GraphScene.Node(
                        id: $0.id, label: $0.label, radius: Float($0.radius), group: $0.group,
                        birth: $0.birth.map(Float.init))
                },
                edges: viewModel.edges.map {
                    GraphScene.Edge(source: $0.source, target: $0.target, weight: Float($0.weight))
                },
                groups: viewModel.communities.map { GraphScene.Group(id: $0.group, name: $0.name) }
            ))
    }
}
