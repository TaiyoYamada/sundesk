//
//  Container+Knowledge.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import FactoryKit
import Foundation
import GraphFeature
import OSLog
import SundeskData
import SundeskDomain
import SundeskMarkdown
import SwiftData

extension Container {
    // MARK: - Infrastructure

    var noteChunker: Factory<any NoteChunking> {
        self { MarkdownChunker() }
            .singleton
    }

    // MARK: - Data

    /// 知識の保存先。Vault ごとに別のファイルにする。開けなければメモリ上に作る。
    var knowledgeModelContainer: Factory<ModelContainer> {
        self {
            let vault = URL(filePath: self.resolvedSettings().vaultDirectory, directoryHint: .isDirectory)
            do {
                return try KnowledgeStore.makeContainer(url: KnowledgeStore.defaultURL(forVault: vault))
            } catch {
                Logger(subsystem: "com.taiyou.sundesk", category: "knowledge")
                    .error("知識の保存先を開けないので、メモリ上に作る: \(error.localizedDescription, privacy: .public)")
                // メモリ上の SwiftData は、スキーマが正しい限り失敗しない
                // swiftlint:disable:next force_try
                return try! KnowledgeStore.makeContainer(url: nil)
            }
        }
        .singleton
    }

    var knowledgeRepository: Factory<any KnowledgeRepository> {
        self { SwiftDataKnowledgeRepository(modelContainer: self.knowledgeModelContainer()) }
            .singleton
    }

    var knowledgeEngine: Factory<any KnowledgeEngine> {
        self { EngineKnowledgeGateway(process: self.engineProcess()) }
    }

    // MARK: - UseCase

    /// 作り直しはアプリに 1 つだけ（同時に 2 つ走らせない）。
    var knowledgeBuilder: Factory<KnowledgeBuilder> {
        self {
            KnowledgeBuilder(
                vault: self.vaultRepository(), markdown: self.markdownParser(), chunker: self.noteChunker(),
                engine: self.knowledgeEngine(), repository: self.knowledgeRepository(), documents: PDFKitTextExtractor()
            )
        }
        .singleton
    }

    var loadKnowledgeGraph: Factory<any LoadKnowledgeGraphUseCase> {
        self { LoadKnowledgeGraphInteractor(repository: self.knowledgeRepository()) }
    }

    var observeKnowledge: Factory<any ObserveKnowledgeUseCase> {
        self { ObserveKnowledgeInteractor(repository: self.knowledgeRepository()) }
    }

    var findConceptSources: Factory<any FindConceptSourcesUseCase> {
        self { FindConceptSourcesInteractor(repository: self.knowledgeRepository()) }
    }

    var loadKnowledgeTimeline: Factory<any LoadKnowledgeTimelineUseCase> {
        self { LoadKnowledgeTimelineInteractor(repository: self.knowledgeRepository(), vault: self.vaultRepository()) }
    }

    // MARK: - ViewModel

    /// ウインドウごとに作る。
    @MainActor
    var graphViewModel: Factory<GraphViewModel> {
        self {
            GraphViewModel(
                loadGraph: self.loadKnowledgeGraph(), observeKnowledge: self.observeKnowledge(),
                rebuildKnowledge: RebuildKnowledgeInteractor(builder: self.knowledgeBuilder()),
                observeBuild: ObserveKnowledgeBuildInteractor(builder: self.knowledgeBuilder()),
                findSources: self.findConceptSources(), loadTimeline: self.loadKnowledgeTimeline())
        }
    }
}
