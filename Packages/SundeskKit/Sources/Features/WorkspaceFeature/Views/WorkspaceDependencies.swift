//
//  WorkspaceDependencies.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import EngineFeature
import NotesFeature

/// ウインドウを作るのに必要なもの。AppFeature（Composition Root）が組み立てて渡す。
///
/// Features は DI のコンテナを知らない。必要なものは、すべてこれで受け取る。
@MainActor
public struct WorkspaceDependencies {
    /// ウインドウ間で共有する。
    public let fileNavigator: FileNavigatorViewModel
    public let engineStatus: EngineStatusViewModel
    /// ウインドウごとに作る。
    public let makeWorkspace: () -> WorkspaceViewModel
    public let makeSearch: () -> SearchViewModel
    public let makeTags: () -> TagsViewModel

    public init(
        fileNavigator: FileNavigatorViewModel,
        engineStatus: EngineStatusViewModel,
        makeWorkspace: @escaping () -> WorkspaceViewModel,
        makeSearch: @escaping () -> SearchViewModel,
        makeTags: @escaping () -> TagsViewModel
    ) {
        self.fileNavigator = fileNavigator
        self.engineStatus = engineStatus
        self.makeWorkspace = makeWorkspace
        self.makeSearch = makeSearch
        self.makeTags = makeTags
    }
}
