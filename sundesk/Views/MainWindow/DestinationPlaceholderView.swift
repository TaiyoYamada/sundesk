//
//  DestinationPlaceholderView.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

/// まだ実装していない機能の画面。
struct DestinationPlaceholderView: View {
    let destination: SidebarDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.systemImage)
        } description: {
            Text("フェーズ \(destination.plannedPhase) で実装します。")
        }
    }
}

#Preview {
    DestinationPlaceholderView(destination: .graph)
}
