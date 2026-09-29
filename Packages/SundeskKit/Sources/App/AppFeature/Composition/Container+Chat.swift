//
//  Container+Chat.swift
//  AppFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import ChatFeature
import FactoryKit
import SundeskData
import SundeskDomain

extension Container {
    // MARK: - Data

    var chatRepository: Factory<any ChatRepository> {
        self { SwiftDataChatRepository(modelContainer: self.knowledgeModelContainer()) }
            .singleton
    }

    var languageModel: Factory<any LanguageModelService> {
        self { LanguageModelRouter(process: self.engineProcess()) }
    }

    // MARK: - UseCase

    var retrieveContext: Factory<any RetrieveContextUseCase> {
        self { RetrieveContextInteractor(repository: self.knowledgeRepository(), engine: self.knowledgeEngine()) }
    }

    var askQuestion: Factory<any AskQuestionUseCase> {
        self {
            AskQuestionInteractor(
                retrieve: self.retrieveContext(), languageModel: self.languageModel(), repository: self.chatRepository()
            )
        }
    }

    var chatHistory: Factory<ChatHistoryInteractor> {
        self { ChatHistoryInteractor(repository: self.chatRepository(), languageModel: self.languageModel()) }
    }

    // MARK: - ViewModel

    /// ウインドウごとに作る。
    @MainActor
    var chatViewModel: Factory<ChatViewModel> {
        self {
            let history = self.chatHistory()
            return ChatViewModel(
                ask: self.askQuestion(), listSessions: history, loadMessages: history, deleteSession: history,
                observeSessions: history, listModels: history,
                rebuildKnowledge: RebuildKnowledgeInteractor(builder: self.knowledgeBuilder()),
                observeBuild: ObserveKnowledgeBuildInteractor(builder: self.knowledgeBuilder()))
        }
    }
}
