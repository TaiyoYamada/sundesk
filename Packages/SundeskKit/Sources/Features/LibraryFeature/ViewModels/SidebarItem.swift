//
//  SidebarItem.swift
//  LibraryFeature
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation

/// サイドバーの項目。
public enum SidebarItem: Hashable, Sendable {
    case all
    case unfiled
    case collection(UUID)
    case tag(String)
}
