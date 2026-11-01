//
//  ReferenceInfoTab.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import SwiftUI

/// インスペクタの「情報」。文献を読み込めていれば、書誌情報の編集欄を出す。
struct ReferenceInfoTab: View {
    @Bindable var viewModel: ReferenceDetailViewModel

    var body: some View {
        if let draft = Binding($viewModel.draft) {
            ReferenceInfoForm(draft: draft, viewModel: viewModel)
        } else {
            ContentUnavailableView("文献が見つかりません", systemImage: "questionmark.folder")
        }
    }
}
