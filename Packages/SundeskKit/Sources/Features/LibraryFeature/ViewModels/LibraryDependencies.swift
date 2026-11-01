//
//  LibraryDependencies.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// ライブラリの画面が使うもの。View はここから ViewModel を作る（View が UseCase を直接触らないように）。
@MainActor
public struct LibraryDependencies {
    private let library: any ManageLibraryUseCase
    private let summarize: any SummarizePaperUseCase

    public init(library: any ManageLibraryUseCase, summarize: any SummarizePaperUseCase) {
        self.library = library
        self.summarize = summarize
    }

    public func makeLibrary() -> LibraryViewModel {
        LibraryViewModel(library: library)
    }

    public func makeDetail(_ referenceID: UUID) -> ReferenceDetailViewModel {
        ReferenceDetailViewModel(referenceID: referenceID, library: library, summarize: summarize)
    }

    public func makeReader(_ referenceID: UUID) -> ReaderViewModel {
        ReaderViewModel(referenceID: referenceID, library: library, detail: makeDetail(referenceID))
    }
}
