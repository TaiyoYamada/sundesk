//
//  FileTreeView.swift
//  NotesFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import AppKit
import SundeskDesignSystem
import SwiftUI

/// 木の中で、フォルダを 1 つのものとして見せる（論文、実験、実行など）。
public struct TreeBundle: Hashable, Sendable {
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    /// 中を開けないか（論文や実験は 1 つのものとして見せる）。false なら、フォルダのまま中も見せる。
    public let isLeaf: Bool

    public init(title: String, subtitle: String? = nil, systemImage: String, isLeaf: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isLeaf = isLeaf
    }
}

/// 木の根（一番上に並べるフォルダ）。
public struct TreeRoot: Hashable, Sendable {
    /// ライブラリの中でのパス。
    public let path: String
    /// 見出し（nil なら中身をそのまま並べる）。
    public let title: String?

    public init(path: String, title: String? = nil) {
        self.path = path
        self.title = title
    }
}

/// Vault のファイルの木。選んだファイルを開き、フォルダでくくる（作る、移す、名前を変える、消す）。
public struct FileTreeView: View {
    @Bindable private var navigator: FileNavigatorViewModel
    private let selectedPath: String?
    private let roots: [TreeRoot]
    private let bundle: (String) -> TreeBundle?
    private let open: (String) -> Void
    private let selectionChanged: (Set<String>) -> Void

    @State private var selection: Set<String> = []
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var dropTarget: String?

    /// 名前を聞く（新しいフォルダ、名前を変える）。
    private enum NamePrompt: Identifiable {
        case newFolder(parent: String)
        case rename(String)

        var id: String {
            switch self {
            case .newFolder(let folder): "new:\(folder)"
            case .rename(let path): "rename:\(path)"
            }
        }
    }

    /// - Parameters:
    ///   - selectedPath: 今開いているファイル。木の選択と連動させる。
    ///   - rootPath: このフォルダの中身を並べる（nil ならすべて）。
    ///   - extraRoots: 続けて、フォルダのまま出すもの（つないだ study-artifact など）。
    ///   - bundle: フォルダを 1 つのもの（論文、実験など）として見せるか。
    ///   - open: ファイルや、1 つのものとして見せるフォルダを選んだときに呼ぶ。
    ///   - selectionChanged: 選んでいるもの（いくつも選べる）が変わったとき。
    public init(
        navigator: FileNavigatorViewModel, selectedPath: String?, rootPath: String? = nil,
        extraRoots: [TreeRoot] = [], bundle: @escaping (String) -> TreeBundle? = { _ in nil },
        selectionChanged: @escaping (Set<String>) -> Void = { _ in }, open: @escaping (String) -> Void
    ) {
        self.navigator = navigator
        self.selectedPath = selectedPath
        self.roots = (rootPath.map { [TreeRoot(path: $0)] } ?? []) + extraRoots
        self.bundle = bundle
        self.selectionChanged = selectionChanged
        self.open = open
    }

    /// 書き換えられる一番上のフォルダ（新しいフォルダや、何もないところへの移動の先）。
    private var mainFolder: String {
        roots.first?.path ?? ""
    }

    private var shownItems: [TreeItem] {
        guard !roots.isEmpty else { return navigator.items.map { TreeItem($0, bundle: bundle) } }
        var items: [TreeItem] = []
        for root in roots {
            guard let item = navigator.filteredItem(at: root.path) else { continue }
            if let title = root.title {
                items.append(TreeItem(item, bundle: bundle, title: title))
            } else {
                items += (item.children ?? []).map { TreeItem($0, bundle: bundle) }
            }
        }
        return items
    }

    public var body: some View {
        Group {
            if let message = navigator.errorMessage {
                ContentUnavailableView {
                    Label("Vault を開けません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    SettingsLink { Text("設定を開く…") }
                }
            } else {
                List(selection: $selection) {
                    OutlineGroup(shownItems, children: \.children) { item in
                        row(item)
                    }
                }
                .listStyle(.sidebar)
                .focusesOnClick()
                .accessibilityIdentifier("file-tree")
                .contextMenu(forSelectionType: String.self) { paths in
                    contextMenu(for: paths)
                } primaryAction: { paths in
                    if paths.count == 1, let path = paths.first { open(path) }
                }
                // Finder と同じく、⌘⌫ や ⌫ で選んだものをゴミ箱へ（ゴミ箱から戻せるので確かめない）
                .onDeleteCommand {
                    let paths = selection.filter { navigator.canEdit($0) }
                    guard !paths.isEmpty else { return }
                    selection = []
                    Task { await navigator.moveToTrash(paths.sorted()) }
                }
                // 何もないところに落としたら、一番上のフォルダへ
                .dropDestination(for: String.self) { paths, _ in
                    guard navigator.canEdit(mainFolder) else { return false }
                    Task { await navigator.move(paths, into: mainFolder) }
                    return true
                }
            }
        }
        .onChange(of: selection) { _, paths in
            selectionChanged(paths)
            guard paths.count == 1, let path = paths.first, path != selectedPath else { return }
            if navigator.isFile(path) || bundle(path) != nil { open(path) }
        }
        .onChange(of: selectedPath, initial: true) { _, path in
            if let path, !selection.contains(path) { selection = [path] }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("名前", text: $promptText)
            Button("キャンセル", role: .cancel) { prompt = nil }
            Button(promptAction) { commitPrompt() }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ item: TreeItem) -> some View {
        let editable = navigator.canEdit(item.id)
        HStack(spacing: 6) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.isBundle ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1).truncationMode(.middle)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .tag(item.id)
        .padding(.vertical, item.subtitle == nil ? 0 : 1)
        .background {
            if dropTarget == item.id { RoundedRectangle(cornerRadius: 4).fill(.tint.opacity(0.2)) }
        }
        .draggable(item.id) {
            Label(item.title, systemImage: item.systemImage).padding(4)
        }
        .modifier(
            FolderDrop(isEnabled: item.acceptsDrop && editable, path: item.id, target: $dropTarget) { paths in
                Task { await navigator.move(paths, into: item.id) }
            })
    }

    // MARK: - メニュー

    @ViewBuilder
    private func contextMenu(for paths: Set<String>) -> some View {
        let sorted = paths.sorted()
        if sorted.count == 1, let path = sorted.first {
            Button("開く") { open(path) }
        }
        let editable = !sorted.isEmpty && sorted.allSatisfy { navigator.canEdit($0) }
        if navigator.canEdit(folderForNew(sorted)) {
            Button("新しいフォルダ…") { ask(.newFolder(parent: folderForNew(sorted))) }
        }
        if editable {
            if sorted.count == 1, let path = sorted.first {
                Button("名前を変える…") { ask(.rename(path)) }
            }
            Menu("移動") {
                ForEach(navigator.folders(under: mainFolder), id: \.self) { folder in
                    Button(folder == mainFolder ? "（一番上）" : String(folder.dropFirst(mainFolder.count + 1))) {
                        Task { await navigator.move(sorted, into: folder) }
                    }
                    .disabled(sorted.contains { folder == $0 || folder.hasPrefix($0 + "/") })
                }
            }
            Divider()
            Button("ゴミ箱に入れる", role: .destructive) { Task { await navigator.moveToTrash(sorted) } }
        }
        if !sorted.isEmpty {
            Divider()
            Button("Finder で表示") {
                NSWorkspace.shared.activateFileViewerSelecting(sorted.map(navigator.fileURL(for:)))
            }
        }
    }

    /// 新しいフォルダを作る場所（選んだフォルダ、ファイルならその親、何も選んでいなければ一番上）。
    private func folderForNew(_ paths: [String]) -> String {
        guard paths.count == 1, let path = paths.first else { return mainFolder }
        if let item = navigator.item(at: path), item.isFolder, bundle(path)?.isLeaf != true { return path }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? mainFolder : parent
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let message = navigator.operationMessage {
                HStack {
                    Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    Spacer()
                    Button("閉じる", systemImage: "xmark") { navigator.operationMessage = nil }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("名前で絞り込む", text: $navigator.filterText)
                    .textFieldStyle(.plain)
                if navigator.isSyncing {
                    ProgressView().controlSize(.mini)
                        .help("Vault を同期しています")
                }
                if navigator.canEdit(mainFolder) {
                    Button("新しいフォルダ", systemImage: "folder.badge.plus") {
                        ask(.newFolder(parent: folderForNew(selection.sorted())))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("新しいフォルダ（選んでいるフォルダの中に作る）")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(.bar)
    }

    // MARK: - 名前

    private var promptTitle: String {
        switch prompt {
        case .newFolder: "新しいフォルダ"
        case .rename: "名前を変える"
        case nil: ""
        }
    }

    private var promptAction: String {
        if case .rename = prompt { return "変える" }
        return "作る"
    }

    private func ask(_ request: NamePrompt) {
        switch request {
        case .newFolder: promptText = "新しいフォルダ"
        case .rename(let path): promptText = (path as NSString).lastPathComponent
        }
        prompt = request
    }

    private func commitPrompt() {
        let name = promptText
        switch prompt {
        case .newFolder(let folder): Task { await navigator.createFolder(named: name, in: folder) }
        case .rename(let path): Task { await navigator.rename(path, to: name) }
        case nil: break
        }
        prompt = nil
    }
}

/// 木に並べる 1 行（1 つのものとして見せるフォルダは、中を隠す）。
struct TreeItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let isBundle: Bool
    let acceptsDrop: Bool
    let children: [TreeItem]?

    init(_ item: NavigatorItem, bundle: (String) -> TreeBundle?, title: String? = nil) {
        id = item.id
        let info = item.isFolder ? bundle(item.id) : nil
        self.title = title ?? info?.title ?? item.name
        subtitle = info?.subtitle
        systemImage = info?.systemImage ?? item.systemImage
        isBundle = info != nil
        // 論文や実験（中を隠すもの）には落とせない。フォルダには落とせる
        acceptsDrop = item.isFolder && info?.isLeaf != true
        children = info?.isLeaf == true ? nil : item.children?.map { TreeItem($0, bundle: bundle) }
    }
}

/// フォルダの行に、ほかの行を落として移す。
private struct FolderDrop: ViewModifier {
    let isEnabled: Bool
    let path: String
    @Binding var target: String?
    let drop: ([String]) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.dropDestination(for: String.self) { paths, _ in
                drop(paths.filter { $0 != path })
                return true
            } isTargeted: { targeted in
                if targeted { target = path } else if target == path { target = nil }
            }
        } else {
            content
        }
    }
}
