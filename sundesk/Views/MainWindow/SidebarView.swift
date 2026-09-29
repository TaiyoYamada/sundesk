//
//  SidebarView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.destinations) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    SidebarView(selection: .constant(.notes))
        .frame(width: 220, height: 400)
}
