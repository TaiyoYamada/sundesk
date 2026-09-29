//
//  EngineStatusButton.swift
//  sundesk
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskPresentation
import SwiftUI

/// ツールバーに置く、エンジンの状態を示すボタン。押すと詳細と操作を出す。
struct EngineStatusButton: View {
    let viewModel: EngineStatusViewModel
    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail.toggle()
        } label: {
            Label {
                Text("エンジン: \(viewModel.title)")
            } icon: {
                EngineIndicatorIcon(indicator: viewModel.indicator)
            }
            .labelStyle(.titleAndIcon)
        }
        .help("AI エンジンの状態")
        .accessibilityIdentifier("engine-status-button")
        .accessibilityValue(viewModel.title)
        .popover(isPresented: $isShowingDetail, arrowEdge: .bottom) {
            EngineStatusDetailView(viewModel: viewModel)
                .padding()
                .frame(width: 320)
        }
    }
}

/// 状態の詳細と、起動・停止のボタン。ポップオーバーと設定画面で使う。
struct EngineStatusDetailView: View {
    let viewModel: EngineStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                EngineIndicatorIcon(indicator: viewModel.indicator)
                Text(viewModel.title)
                    .font(.headline)
                Spacer()
                if viewModel.indicator == .working {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let detail = viewModel.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = viewModel.lastError, error != viewModel.detail {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                SettingsLink {
                    Text("設定…")
                }
                Spacer()
                if viewModel.canStop {
                    Button("停止") { Task { await viewModel.stop() } }
                } else {
                    Button("起動") { Task { await viewModel.start() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canStart)
                }
            }
        }
    }
}

struct EngineIndicatorIcon: View {
    let indicator: EngineStatusViewModel.Indicator

    var body: some View {
        Image(systemName: indicator.symbolName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(indicator.color)
            .accessibilityHidden(true)
    }
}

extension EngineStatusViewModel.Indicator {
    var symbolName: String {
        switch self {
        case .idle: "circle"
        case .working: "circle.dotted"
        case .ready: "circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .working: .orange
        case .ready: .green
        case .error: .red
        }
    }
}
