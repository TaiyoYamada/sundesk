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
import LibraryFeature
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
    public let makeLibrary: () -> LibraryViewModel
    public let makePaper: (String) -> PaperViewModel
    public let makeExperiment: (String) -> ExperimentViewModel
    public let makeComparison: ([String]) -> ComparisonViewModel
    /// ~/Research のプロジェクトと実行の画面。
    public let research: ResearchScreenFactory
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
        makeLibrary: @escaping () -> LibraryViewModel,
        makePaper: @escaping (String) -> PaperViewModel,
        makeExperiment: @escaping (String) -> ExperimentViewModel,
        makeComparison: @escaping ([String]) -> ComparisonViewModel,
        research: ResearchScreenFactory,
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
        self.makeLibrary = makeLibrary
        self.makePaper = makePaper
        self.makeExperiment = makeExperiment
        self.makeComparison = makeComparison
        self.research = research
        self.makeChat = makeChat
        self.makeLab = makeLab
        self.makeForge = makeForge
        self.makeScratch = makeScratch
        self.makeModels = makeModels
        self.makeImages = makeImages
    }
}
