//
//  FileSchemeHandler.swift
//  SundeskWebView
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import UniformTypeIdentifiers
import WebKit

/// 独自の URL スキームへの要求に、フォルダの中のファイルで応える。
///
/// `file://` でページを開くと、ページからディスク上の任意のファイルが読めてしまう。
/// 独自スキームにして、決めたフォルダの中だけを返すようにする。
nonisolated public struct FileSchemeHandler: URLSchemeHandler, Sendable {
    private let root: @Sendable () -> URL

    public init(root: @escaping @Sendable () -> URL) {
        self.root = root
    }

    public func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { continuation in
            do {
                guard let url = request.url, let file = file(for: url) else { throw URLError(.fileDoesNotExist) }
                let data = try Data(contentsOf: file)
                let mimeType =
                    UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let isText = mimeType.hasPrefix("text/") || mimeType.contains("javascript") || mimeType.contains("json")
                continuation.yield(
                    .response(
                        URLResponse(
                            url: url,
                            mimeType: mimeType,
                            expectedContentLength: data.count,
                            textEncodingName: isText ? "utf-8" : nil
                        )
                    )
                )
                continuation.yield(.data(data))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// URL のパスを、フォルダの中のファイルに直す。フォルダの外を指すなら nil。
    func file(for url: URL) -> URL? {
        let root = root().standardizedFileURL
        let path = url.path(percentEncoded: false)
        let file = root.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        return file
    }
}
