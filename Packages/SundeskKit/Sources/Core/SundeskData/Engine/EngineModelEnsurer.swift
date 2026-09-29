//
//  EngineModelEnsurer.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import Foundation
import SundeskEngineClient

/// モデルが手元になければ、使う前に取り込む。
///
/// エンジンはモデルを勝手にダウンロードしない（手元にないと 404 を返す）。使うときに、ここで先に取り込む。
actor EngineModelEnsurer {
    static let shared = EngineModelEnsurer()

    /// 手元にあると分かっているモデル。
    private var present: Set<String> = []

    /// - Parameter downloading: 取り込みを始めるときに呼ぶ（画面に「ダウンロード中」を出すため）。
    func ensure(
        _ id: String, client: EngineClient, downloading: @Sendable () -> Void = {}
    ) async throws(EngineClientError) {
        guard !present.contains(id) else { return }
        let models = try await client.get("models", as: ModelsResponse.self)
        present.formUnion(models.models.map(\.id))
        guard !present.contains(id) else { return }
        downloading()
        do {
            for try await _ in client.stream("models/download", body: DownloadRequest(id: id), as: DownloadLine.self) {}
        } catch let error as EngineClientError {
            throw error
        } catch {
            throw .transport(error.localizedDescription)
        }
        present.insert(id)
    }

    /// 消したモデルを忘れる。
    func forget(_ id: String) {
        present.remove(id)
    }
}
