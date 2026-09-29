//
//  WorkspaceDependencies.swift
//  WorkspaceFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import ChatFeature
import EngineFeature
import GraphFeature
import ImagesFeature
import LabFeature
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
    public let makeGraph: () -> GraphViewModel
    public let makeChat: () -> ChatViewModel
    public let makeLab: () -> LabViewModel
    public let makeForge: () -> ForgeViewModel
    public let makeScratch: () -> ScratchViewModel
    public let makeModels: () -> ModelsViewModel
    public let makeImages: () -> ImagesViewModel

    public init(
        fileNavigator: FileNavigatorViewModel,
        engineStatus: EngineStatusViewModel,
        makeWorkspace: @escaping () -> WorkspaceViewModel,
        makeSearch: @escaping () -> SearchViewModel,
        makeTags: @escaping () -> TagsViewModel,
        makeGraph: @escaping () -> GraphViewModel,
        makeChat: @escaping () -> ChatViewModel,
        makeLab: @escaping () -> LabViewModel,
        makeForge: @escaping () -> ForgeViewModel,
        makeScratch: @escaping () -> ScratchViewModel,
        makeModels: @escaping () -> ModelsViewModel,
        makeImages: @escaping () -> ImagesViewModel
    ) {
        self.fileNavigator = fileNavigator
        self.engineStatus = engineStatus
        self.makeWorkspace = makeWorkspace
        self.makeSearch = makeSearch
        self.makeTags = makeTags
        self.makeGraph = makeGraph
        self.makeChat = makeChat
        self.makeLab = makeLab
        self.makeForge = makeForge
        self.makeScratch = makeScratch
        self.makeModels = makeModels
        self.makeImages = makeImages
    }
}
