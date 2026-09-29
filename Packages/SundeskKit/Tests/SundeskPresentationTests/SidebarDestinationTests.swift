//
//  SidebarDestinationTests.swift
//  SundeskPresentationTests
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import Testing

@Suite("SidebarDestination")
struct SidebarDestinationTests {
    @Test("すべての項目が、ちょうど 1 つのセクションに属する")
    func everyDestinationBelongsToExactlyOneSection() {
        let listed = SidebarSection.allCases.flatMap(\.destinations)

        #expect(listed.count == SidebarDestination.allCases.count)
        #expect(Set(listed) == Set(SidebarDestination.allCases))
    }

    @Test("空のセクションはない", arguments: SidebarSection.allCases)
    func noEmptySection(section: SidebarSection) {
        #expect(!section.destinations.isEmpty)
    }

    @Test("名前とアイコンが空でない", arguments: SidebarDestination.allCases)
    func hasTitleAndSymbol(destination: SidebarDestination) {
        #expect(!destination.title.isEmpty)
        #expect(!destination.systemImage.isEmpty)
    }
}
