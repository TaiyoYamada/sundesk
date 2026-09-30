//
//  LabScreen.swift
//  LabFeature
//
//  Created by 山田大陽 on 2026/09/29.
//

import SundeskDesignSystem
import SwiftUI

/// 実験室のタブ。主役は Python のスクリプトのエディタで、左にスクリプトの一覧、右に道具のパネルを出し入れする。
///
/// 道具（トークン、Attention、LoRA、量子化、記録…）は、上の「道具」のメニューか ⌃⌘T で右のパネルに開く。
public struct LabScreen: View {
    @Bindable private var viewModel: LabViewModel
    private let forge: ForgeViewModel
    private let scratch: ScratchViewModel

    @AppStorage("lab.showsScripts") private var showsScripts = true
    @AppStorage("lab.showsTools") private var showsTools = false
    @AppStorage("lab.toolsWidth") private var toolsWidth = 420.0
    @State private var sessions = ScriptEditorSessions()
    @State private var renameRequested = false

    /// 道具のパネルの幅の範囲。ウインドウの幅に合わせて変えると、分割ビューの制約の計算が終わらなくなるので固定する。
    private static let toolsWidthRange = 320.0...900.0

    public init(viewModel: LabViewModel, forge: ForgeViewModel, scratch: ScratchViewModel) {
        self.viewModel = viewModel
        self.forge = forge
        self.scratch = scratch
    }

    public var body: some View {
        HStack(spacing: 0) {
            if showsScripts {
                ScriptListView(viewModel: scratch, sessions: sessions) { renameRequested = true }
                    .frame(width: 210)
                Divider()
            }
            ScratchView(
                viewModel: scratch, sessions: sessions, lab: viewModel, showsScripts: $showsScripts,
                showsTools: $showsTools, renameRequested: $renameRequested
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsTools {
                PanelResizeHandle(width: $toolsWidth, range: Self.toolsWidthRange)
                ToolPanel(viewModel: viewModel, forge: forge, isPresented: $showsTools)
                    .frame(width: toolsWidth.clamped(to: Self.toolsWidthRange))
            }
        }
        // 中身の最小の大きさを外に伝えない（ウインドウの分割ビューが、最小の大きさの変化を受けて
        // 制約の計算を繰り返し、落ちるのを防ぐ。SplitPane の説明を参照）
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .task { await scratch.load() }
        .task { await viewModel.load() }
        .task { await viewModel.observeRecords() }
        // 工房の道具を開いたときに、モデルとフォルダを読む
        .task(id: showsTools ? viewModel.section.rawValue : "") {
            if showsTools, viewModel.section.usesForge { await forge.load() }
        }
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
