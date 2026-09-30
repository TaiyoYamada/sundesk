//
//  ImageFileActions.swift
//  ImagesFeature
//
//  Created by 山田大陽 on 2026/09/30.
//

import AppKit
import CoreTransferable
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 画像のファイルを、クリップボード、Finder、保存パネルに渡す。
enum ImageFileActions {
    /// クリップボードへ写す。画像として貼れるアプリには画像を、Finder にはファイルを渡す。
    static func copy(_ urls: [URL]) {
        let items = urls.map { url in
            let item = NSPasteboardItem()
            if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items)
    }

    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// 書き出す。1 枚なら保存パネル、何枚かならフォルダを選ぶ。
    static func export(_ ids: [UUID], viewModel: ImagesViewModel) {
        if ids.count == 1, let id = ids.first {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = viewModel.suggestedFileName(for: id)
            panel.canCreateDirectories = true
            present(panel) { url in viewModel.export(id, to: url) }
        } else if !ids.isEmpty {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "書き出す"
            panel.message = "\(ids.count) 枚の画像を書き出すフォルダを選んでください"
            present(panel) { url in viewModel.export(ids, toDirectory: url) }
        }
    }

    private static func present(_ panel: NSSavePanel, completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}

/// ドラッグで Finder や他のアプリへ渡す画像のファイル。
nonisolated struct DraggedImageFile: Transferable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    /// 渡すときのファイル名。
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { file in
            // 元のファイル（アプリのデータ）を動かされないよう、名前を付けた写しを渡す
            let directory = URL.temporaryDirectory.appending(path: "sundesk-drag-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appending(path: file.name)
            try FileManager.default.copyItem(at: file.url, to: copy)
            return SentTransferredFile(copy)
        }
    }
}

/// サムネイルを作り、覚えておく。
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    /// `maxPixelSize` はだいたいでよい（256 ごとに丸めて、同じものを使い回す）。
    func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let bucket = max(256, Int((maxPixelSize / 256).rounded(.up)) * 256)
        let key = "\(url.path)#\(bucket)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = await Self.makeThumbnail(url: url, maxPixelSize: bucket) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        cache.setObject(result, forKey: key)
        return result
    }

    @concurrent
    nonisolated private static func makeThumbnail(url: URL, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// サムネイルを読み込んで出す。読み込むまでは、灰色の四角。
struct ThumbnailImage: View {
    let url: URL
    let maxPixelSize: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: "\(url.path)#\(Int(maxPixelSize / 256))") {
            image = await ThumbnailCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}

/// 押していた修飾キーを、選び方に直す。
@MainActor
func currentSelectionModifier() -> SelectionModifier {
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) { return .extend }
    if flags.contains(.command) { return .toggle }
    return .none
}
